'use strict';
// PROTOTYP: wykrywanie modow w repozytorium po tagach wydan.
//
// Sedno zmiany wzgledem sources.json: Patcher NIE dostaje listy modow. Dostaje
// REPOZYTORIUM, przeglada jego wydania, rozklada tagi wg konwencji
//
//     <mod>-<x.y.z>          np. mapatlas-0.4.0
//
// grupuje po nazwie moda i dla kazdego bierze NAJWYZSZA wersje. Nowy mod w repo
// pojawia sie w planie sam, bez zmiany czegokolwiek po stronie Patchera.
//
//   node MIGRATION/reference/discover.js AtmatiAdi/TerraFirmaGreg-Modern_Optimisation
//
// Ten plik jest dowodem, ze projekt dziala na zywym repozytorium - docelowo trafia
// do silnika Patchera jako engine/discover.js (patrz PATCHER-CHANGES.md).

const https = require('https');

const API = 'https://api.github.com';
const PER_PAGE = 100;
const MAX_PAGES = 5;   // 500 wydan; dalej i tak nie ma czego szukac

/** Tag -> { mod, version }. Bez wersji na koncu = nie nasz tag, pomijamy. */
const TAG_RE = /^(.+?)-v?(\d+(?:\.\d+)*)$/;

function parseTag(tag) {
  const m = TAG_RE.exec(String(tag).trim());
  if (!m) return null;
  return { mod: m[1].toLowerCase(), version: m[2] };
}

/**
 * Porownanie wersji ODCINKAMI LICZBOWO. Porownanie napisow dawaloby
 * "0.10.0" < "0.9.0" i cicho instalowaloby starszy jar.
 */
function cmpVersion(a, b) {
  const A = a.split('.').map(Number);
  const B = b.split('.').map(Number);
  for (let i = 0; i < Math.max(A.length, B.length); i++) {
    const x = A[i] || 0, y = B[i] || 0;
    if (x !== y) return x - y;
  }
  return 0;
}

function get(url, token) {
  return new Promise((resolve, reject) => {
    const headers = {
      'User-Agent': 'TFG-Patcher-discover',
      Accept: 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
    };
    if (token) headers.Authorization = 'Bearer ' + token;
    https.get(url, { headers }, res => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        res.resume();
        // Przekierowanie zdarza sie m.in. po ZMIANIE NAZWY repozytorium - stara
        // nazwa dziala dalej, wiec rename nie psuje niczego u odbiorcow.
        return resolve(get(res.headers.location, token));
      }
      const chunks = [];
      res.on('data', c => chunks.push(c));
      res.on('end', () => {
        const body = Buffer.concat(chunks).toString('utf8');
        if (res.statusCode !== 200) return reject(new Error(`HTTP ${res.statusCode}: ${body.slice(0, 200)}`));
        resolve(JSON.parse(body));
      });
    }).on('error', reject);
  });
}

/**
 * @returns {{id, version, tag, published, assets, replaceGlob, notes}[]}
 *          po jednym wpisie na moda - zawsze najnowsza wersja
 */
async function discover(repo, { token = null, prerelease = false, log = () => {} } = {}) {
  const releases = [];
  for (let page = 1; page <= MAX_PAGES; page++) {
    const batch = await get(`${API}/repos/${repo}/releases?per_page=${PER_PAGE}&page=${page}`, token);
    releases.push(...batch);
    log(`  strona ${page}: ${batch.length} wydan`);
    if (batch.length < PER_PAGE) break;
  }

  const best = new Map();
  const skipped = [];

  for (const rel of releases) {
    if (rel.draft) { skipped.push(`${rel.tag_name} (draft)`); continue; }
    if (rel.prerelease && !prerelease) { skipped.push(`${rel.tag_name} (prerelease)`); continue; }

    const parsed = parseTag(rel.tag_name);
    if (!parsed) { skipped.push(`${rel.tag_name} (tag nie pasuje do <mod>-<x.y.z>)`); continue; }

    // Zalaczniki moda: najpierw te nazwane po nim, w ostatecznosci wszystkie jary.
    const jars = (rel.assets || []).filter(a => a.name.toLowerCase().endsWith('.jar'));
    const own = jars.filter(a => a.name.toLowerCase().startsWith(parsed.mod));
    const assets = own.length ? own : jars;
    if (!assets.length) { skipped.push(`${rel.tag_name} (brak zalacznika .jar)`); continue; }

    const prev = best.get(parsed.mod);
    if (prev && cmpVersion(prev.version, parsed.version) >= 0) continue;

    best.set(parsed.mod, {
      id: parsed.mod,
      version: parsed.version,
      tag: rel.tag_name,
      published: rel.published_at,
      notes: (rel.body || '').trim().split('\n')[0] || null,
      assets: assets.map(a => ({ name: a.name, size: a.size, url: a.url })),
      // Ktore STARSZE pliki usunac przy wgraniu - wyprowadzone z nazwy moda,
      // wiec nikt nie musi tego wpisywac recznie i nie da sie zapomniec.
      replaceGlob: parsed.mod + '-*.jar',
    });
  }

  return { mods: [...best.values()].sort((a, b) => a.id.localeCompare(b.id)), skipped, total: releases.length };
}

module.exports = { discover, parseTag, cmpVersion };

// --------------------------------------------------------------------- CLI

if (require.main === module) {
  const repo = process.argv[2] || 'AtmatiAdi/TerraFirmaGreg-Modern_Optimisation';
  const token = process.env.TFG_GITHUB_TOKEN || process.env.GITHUB_TOKEN || null;

  console.log(`Repozytorium: ${repo}${token ? ' [token]' : ' [anonimowo]'}`);
  discover(repo, { token, log: m => console.log(m) })
    .then(({ mods, skipped, total }) => {
      console.log(`\nWydan przejrzanych: ${total}`);
      console.log(`Modow wykrytych:    ${mods.length}\n`);
      for (const m of mods) {
        console.log(`  ${m.id.padEnd(16)} ${m.version.padEnd(10)} tag=${m.tag}`);
        for (const a of m.assets) console.log(`      ${a.name} (${Math.round(a.size / 1024)} KB)`);
        console.log(`      usunie starsze: ${m.replaceGlob}`);
        if (m.notes) console.log(`      opis: ${m.notes}`);
      }
      if (skipped.length) {
        console.log(`\nPominiete wydania (${skipped.length}):`);
        for (const s of skipped.slice(0, 15)) console.log('  - ' + s);
      }
    })
    .catch(e => { console.log('BLAD: ' + e.message); process.exit(1); });
}

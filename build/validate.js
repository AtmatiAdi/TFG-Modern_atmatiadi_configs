'use strict';
// Walidacja manifestu presetu wzgledem docs/PRESET-FORMAT.md (format 1).
//
// To samo sprawdzenie robi Patcher PO POBRANIU pliku - lepiej pokazac "preset
// uszkodzony", niz wykonac polowe planu. Tutaj chodzi o to, zeby uszkodzony preset
// nigdy nie wyszedl z repozytorium.
//
//   node build/validate.js                      preset.json
//   node build/validate.js preset.json --assets assets
//
// Kod wyjscia: 0 = czysto, 1 = bledy.

const fs = require('fs');
const path = require('path');

const OPS = ['setKey', 'setJson', 'installAsset', 'installRelease', 'disableMods'];
const STYLES = ['toml', 'properties', 'options', 'ini'];
const SIDES = ['client', 'server', 'both'];
const BUILTIN_VARS = ['instanceDir', 'gameDir', 'toolsDir', 'profile'];
const PATH_PREFIXES = ['@instance/', '@tools/'];

const errors = [];
const warnings = [];
const err = (where, msg) => errors.push(`${where}: ${msg}`);
const warn = (where, msg) => warnings.push(`${where}: ${msg}`);

// ------------------------------------------------------------------- pomocnicze

/** Wszystkie {nazwy} w napisie; {{ to klamra literalna. */
function varsIn(text) {
  const out = [];
  const re = /\{([a-zA-Z_][a-zA-Z0-9_]*)\}/g;
  let m;
  while ((m = re.exec(String(text).replace(/\{\{/g, ''))) !== null) out.push(m[1]);
  return out;
}

/** Rekurencyjnie kazdy napis w strukturze, z pominieciem komentarzy "_". */
function strings(node, where, hit) {
  if (typeof node === 'string') return hit(node, where);
  if (Array.isArray(node)) return node.forEach((v, i) => strings(v, `${where}[${i}]`, hit));
  if (node && typeof node === 'object') {
    for (const [k, v] of Object.entries(node)) {
      if (k === '_') continue;
      strings(v, `${where}.${k}`, hit);
    }
  }
}

function globToRe(glob) {
  return new RegExp('^' + glob.replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*') + '$');
}

/** Sciezka wychodzaca poza instancje jest odrzucana - manifest przychodzi z sieci. */
function checkPath(value, where) {
  let p = String(value);
  for (const prefix of PATH_PREFIXES) {
    if (p.startsWith(prefix)) { p = p.slice(prefix.length); break; }
  }
  if (p.startsWith('@')) err(where, `nieznany przedrostek sciezki w "${value}"`);
  if (/^[a-zA-Z]:/.test(p) || p.startsWith('/') || p.startsWith('\\')) {
    err(where, `sciezka bezwzgledna jest zabroniona: "${value}"`);
  }
  if (p.split(/[\\/]/).includes('..')) {
    err(where, `wyjscie poza katalog instancji jest zabronione: "${value}"`);
  }
  if (p.includes('\\')) warn(where, `uzyj ukosnika "/" zamiast "\\" w "${value}"`);
}

function need(obj, field, where, type) {
  const v = obj[field];
  if (v === undefined || v === null || v === '') { err(where, `brak pola "${field}"`); return false; }
  if (type === 'array' && !Array.isArray(v)) { err(where, `"${field}" musi byc lista`); return false; }
  if (type === 'string' && typeof v !== 'string') { err(where, `"${field}" musi byc napisem`); return false; }
  if (type === 'array' && !v.length) { err(where, `"${field}" nie moze byc puste`); return false; }
  return true;
}

// ------------------------------------------------------------------ walidacja

function validate(preset, assetsDir) {
  if (preset.formatVersion !== 1) {
    err('preset', `formatVersion musi byc 1 (jest: ${JSON.stringify(preset.formatVersion)})`);
    return;
  }
  ['id', 'name', 'version'].forEach(f => need(preset, f, 'preset', 'string'));

  // --- grupy
  const groupIds = new Set();
  if (need(preset, 'groups', 'preset', 'array')) {
    preset.groups.forEach((g, i) => {
      const w = `groups[${i}]`;
      ['id', 'label'].forEach(f => need(g, f, w, 'string'));
      if (groupIds.has(g.id)) err(w, `powtorzone id grupy "${g.id}"`);
      groupIds.add(g.id);
    });
  }

  // --- profile
  const profileVars = new Set();
  const profileIds = new Set();
  if (need(preset, 'profiles', 'preset', 'array')) {
    const ids = profileIds;
    let defaults = 0;
    preset.profiles.forEach((p, i) => {
      const w = `profiles[${i}]`;
      ['id', 'label'].forEach(f => need(p, f, w, 'string'));
      if (ids.has(p.id)) err(w, `powtorzone id profilu "${p.id}"`);
      ids.add(p.id);
      if (p.default === true) defaults++;
      if (p.side && !SIDES.includes(p.side)) err(w, `side musi byc jednym z: ${SIDES.join(', ')}`);
      if (p.vars) Object.keys(p.vars).forEach(k => profileVars.add(k));
    });
    if (defaults !== 1) err('profiles', `dokladnie jeden profil ma miec "default": true (jest ${defaults})`);
  }

  // --- zmienne: profilowe przeslaniaja presetowe, wbudowane dostarcza Patcher
  const known = new Set([
    ...Object.keys(preset.vars || {}).filter(k => k !== '_' && !k.startsWith('_')),
    ...profileVars,
    ...BUILTIN_VARS,
  ]);
  for (const [name, value] of Object.entries(preset.vars || {})) {
    if (name.startsWith('_')) continue;
    const t = typeof value;
    if (t !== 'string' && t !== 'number' && !Array.isArray(value)) {
      err(`vars.${name}`, 'wartosc musi byc napisem, liczba albo lista napisow');
    }
    if (Array.isArray(value) && value.some(v => typeof v !== 'string')) {
      err(`vars.${name}`, 'lista moze zawierac tylko napisy');
    }
  }

  // --- zrodla modow (repozytoria, NIE lista modow)
  if (preset.modSources !== undefined) {
    if (!Array.isArray(preset.modSources)) {
      err('preset', '"modSources" musi byc lista');
    } else {
      const repos = new Set();
      preset.modSources.forEach((src, i) => {
        const w = `modSources[${i}]${src.repo ? ` (${src.repo})` : ''}`;
        if (need(src, 'repo', w, 'string') && !/^[\w.-]+\/[\w.-]+$/.test(src.repo)) {
          err(w, `"repo" ma miec postac wlasciciel/repozytorium (jest: "${src.repo}")`);
        }
        if (repos.has(src.repo)) err(w, `to samo repozytorium wymienione dwa razy: "${src.repo}"`);
        repos.add(src.repo);

        if (src.group && !groupIds.has(src.group)) err(w, `nieznana grupa "${src.group}"`);
        if (src.side && !SIDES.includes(src.side)) err(w, `side musi byc jednym z: ${SIDES.join(', ')}`);
        if (src.prerelease !== undefined && typeof src.prerelease !== 'boolean') {
          err(w, '"prerelease" musi byc true albo false');
        }
        for (const field of ['only', 'except']) {
          const v = src[field];
          if (v === undefined || v === null) continue;
          if (!Array.isArray(v) || v.some(x => typeof x !== 'string')) {
            err(w, `"${field}" musi byc lista nazw modow`);
          }
        }
        if (src.mods !== undefined) {
          if (!src.mods || typeof src.mods !== 'object' || Array.isArray(src.mods)) {
            err(w, '"mods" musi byc obiektem {nazwa-moda: {opis}}');
          } else {
            for (const [modId, meta] of Object.entries(src.mods)) {
              if (modId !== modId.toLowerCase()) {
                err(w, `nazwa moda "${modId}" ma byc malymi literami (tak jak w tagu)`);
              }
              if (!meta || typeof meta !== 'object' || Array.isArray(meta)) {
                err(w, `"mods.${modId}" musi byc obiektem`);
                continue;
              }
              if (meta.side && !SIDES.includes(meta.side)) {
                err(w, `"mods.${modId}.side" musi byc jednym z: ${SIDES.join(', ')}`);
              }
              if (Array.isArray(src.only) && src.only.length && !src.only.includes(modId)) {
                warn(w, `"mods.${modId}" opisuje moda odcietego przez "only" - opis nigdy sie nie pokaze`);
              }
              if (Array.isArray(src.except) && src.except.includes(modId)) {
                warn(w, `"mods.${modId}" opisuje moda z listy "except" - opis nigdy sie nie pokaze`);
              }
            }
          }
        }
      });
    }
  }

  // --- pozycje
  if (!need(preset, 'items', 'preset', 'array')) return;
  const itemIds = new Set();

  preset.items.forEach((item, i) => {
    const w = `items[${i}]${item.id ? ` (${item.id})` : ''}`;
    ['id', 'group', 'side', 'title', 'doc', 'why'].forEach(f => need(item, f, w, 'string'));

    if (itemIds.has(item.id)) err(w, `powtorzone id pozycji "${item.id}"`);
    itemIds.add(item.id);
    if (item.group && !groupIds.has(item.group)) err(w, `nieznana grupa "${item.group}"`);
    if (item.side && !SIDES.includes(item.side)) err(w, `side musi byc jednym z: ${SIDES.join(', ')}`);

    // "selected": bool albo { <profil>: bool, "*": bool }. Literowka w nazwie profilu
    // byla by inaczej niewidoczna - pozycja po cichu zaznaczalaby sie wszedzie.
    if (item.selected !== undefined && typeof item.selected !== 'boolean') {
      if (!item.selected || typeof item.selected !== 'object' || Array.isArray(item.selected)) {
        err(w, '"selected" musi byc true/false albo obiektem {profil: bool}');
      } else {
        for (const [key, value] of Object.entries(item.selected)) {
          if (key !== '*' && !profileIds.has(key)) {
            err(w, `"selected" wskazuje nieznany profil "${key}" (znane: ${[...profileIds].join(', ')})`);
          }
          if (typeof value !== 'boolean') err(w, `"selected.${key}" musi byc true albo false`);
        }
      }
    }

    if (!need(item, 'changes', w, 'array')) return;

    item.changes.forEach((c, j) => {
      const cw = `${w}.changes[${j}]`;
      if (!OPS.includes(c.op)) { err(cw, `nieznana operacja "${c.op}" (znane: ${OPS.join(', ')})`); return; }

      if (c.op === 'setKey') {
        need(c, 'file', cw, 'string') && checkPath(c.file, cw + '.file');
        need(c, 'key', cw, 'string');
        if (typeof c.value !== 'string') err(cw, '"value" musi byc napisem (takze dla liczb i true/false)');
        if (!STYLES.includes(c.style)) err(cw, `style musi byc jednym z: ${STYLES.join(', ')}`);
        if (c.section && !['toml', 'ini'].includes(c.style)) {
          err(cw, `"section" ma sens tylko przy style toml/ini (jest: ${c.style})`);
        }
      }

      if (c.op === 'setJson') {
        need(c, 'file', cw, 'string') && checkPath(c.file, cw + '.file');
        need(c, 'key', cw, 'string');
        if (typeof c.value !== 'string') err(cw, '"value" musi byc napisem');
        if (c.key && c.key.includes('.')) warn(cw, 'klucze zagniezdzone nie sa obslugiwane');
      }

      if (c.op === 'installAsset') {
        need(c, 'asset', cw, 'string');
        need(c, 'target', cw, 'string') && checkPath(c.target, cw + '.target');
        if (c.unpack !== undefined && c.unpack !== null && c.unpack !== 'zip') {
          err(cw, `"unpack" moze byc tylko "zip" albo pominiete (jest: ${JSON.stringify(c.unpack)})`);
        }
        if (c.unpack === 'zip' && c.onlyIfMissing) {
          warn(cw, '"onlyIfMissing" przy rozpakowywaniu dotyczy calego katalogu - upewnij sie, ze o to chodzi');
        }
      }

      if (c.op === 'installRelease') {
        need(c, 'repo', cw, 'string');
        need(c, 'asset', cw, 'string');
        need(c, 'target', cw, 'string') && checkPath(c.target, cw + '.target');
        if (c.repo && !/^[\w.-]+\/[\w.-]+$/.test(c.repo)) {
          err(cw, `"repo" ma miec postac wlasciciel/repozytorium (jest: "${c.repo}")`);
        }
        if (!c.replaceGlob) {
          warn(cw, 'bez "replaceGlob" starsze wersje zostana obok nowej - gra wystartuje z dwoma kopiami moda');
        }
      }

      if (c.op === 'disableMods') {
        need(c, 'prefixes', cw, 'array');
        if (!c.scan || !Array.isArray(c.scan.tokens) || !c.scan.tokens.length) {
          err(cw, '"scan.tokens" jest OBOWIAZKOWY - mods.toml nie wystarcza do wykrycia zaleznosci');
        } else {
          for (const t of c.scan.tokens) {
            if (!t.includes('/')) warn(cw, `token "${t}" jest szeroki - waskie tokeny to np. "xaero/common/"`);
          }
        }
      }
    });
  });

  // --- zmienne uzyte, ale nieznane
  strings(preset.items, 'items', (text, where) => {
    for (const name of varsIn(text)) {
      if (!known.has(name)) err(where, `nieznana zmienna {${name}}`);
    }
  });
  strings(preset.vars || {}, 'vars', (text, where) => {
    for (const name of varsIn(text)) {
      if (!known.has(name)) err(where, `nieznana zmienna {${name}}`);
    }
  });

  // --- zalaczniki: czy to, na co wskazuje manifest, w ogole istnieje
  if (assetsDir) {
    const files = fs.existsSync(assetsDir) ? walk(assetsDir) : [];
    for (const item of preset.items) {
      for (const c of item.changes || []) {
        if (c.op !== 'installAsset' || !c.asset) continue;
        const mask = resolveVars(c.asset, preset);
        if (!files.some(f => globToRe(mask).test(path.basename(f)))) {
          err(`items (${item.id})`, `brak zalacznika pasujacego do "${mask}" w ${assetsDir}`);
        }
      }
    }
  }
}

/** Podstawienie samych zmiennych presetu - do sprawdzenia zalacznikow. */
function resolveVars(text, preset) {
  return String(text).replace(/\{([a-zA-Z_][a-zA-Z0-9_]*)\}/g, (whole, name) => {
    const v = (preset.vars || {})[name];
    if (v === undefined) return whole;
    return Array.isArray(v) ? v.join(' ') : String(v);
  });
}

function walk(dir) {
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, entry.name);
    if (entry.isDirectory()) out.push(...walk(p));
    else out.push(p);
  }
  return out;
}

// ----------------------------------------------------------------------- main

function main(argv) {
  let file = 'preset.json';
  let assetsDir = null;
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--assets') assetsDir = argv[++i];
    else if (!argv[i].startsWith('-')) file = argv[i];
  }

  let preset;
  try {
    preset = JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (e) {
    console.log(`BLAD: nie da sie wczytac ${file}: ${e.message}`);
    return 1;
  }

  validate(preset, assetsDir);

  warnings.forEach(w => console.log('  UWAGA  ' + w));
  errors.forEach(e => console.log('  BLAD   ' + e));

  if (errors.length) {
    console.log(`\n${file}: ${errors.length} bledow, ${warnings.length} ostrzezen - NIE WYDAWAJ.`);
    return 1;
  }
  const items = (preset.items || []).length;
  const changes = (preset.items || []).reduce((n, i) => n + (i.changes || []).length, 0);
  console.log(`\n${file}: OK - ${items} pozycji, ${changes} operacji, `
    + `${(preset.profiles || []).length} profile, ${warnings.length} ostrzezen.`);
  return 0;
}

process.exit(main(process.argv.slice(2)));

const fs = require('fs');
const c = require('milkdrop-preset-converter');
const milk = fs.readFileSync('source.milk', 'utf8');
(async () => {
  try {
    const res = await c.convertPreset(milk);
    const out = (typeof res === 'string') ? res : JSON.stringify(res);
    fs.writeFileSync('dragon_ref_preset.json', out);
    const obj = (typeof res === 'string') ? JSON.parse(res) : res;
    console.log('OK keys:', Object.keys(obj).join(','));
    console.log('waves:', (obj.waves||[]).length, 'has warp:', !!obj.warp, 'has comp:', !!obj.comp);
    console.log('baseVals.nwavemode:', obj.baseVals && obj.baseVals.nwavemode);
  } catch (e) {
    console.error('CONVERT ERROR:', e && e.message ? e.message : e);
    process.exit(1);
  }
})();

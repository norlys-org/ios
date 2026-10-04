// Packs the website's globe geometry into the compact binaries the Aurora globe widget reads
// (norlysWidget/AuroraGlobe/Globe*.bin), so the widget never parses megabytes of GeoJSON:
//
//   'NGEO' | u32 rings | u32 points | u32 offsets[rings + 1] | i16 lon, i16 lat per point
//
// with longitudes scaled by 32767 / 180 and latitudes by 32767 / 90 (under 0.003° of error).
//
// Usage: node scripts/pack-globe-assets.mjs [path to the website, default ../norlys/website]
import fs from 'node:fs'
import { createRequire } from 'node:module'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const here = path.dirname(fileURLToPath(import.meta.url))
const website = path.resolve(process.argv[2] ?? path.join(here, '../../norlys/website'))
const assets = path.join(website, 'app/components/apps/models/Map/assets')
const out = path.join(here, '../norlysWidget/AuroraGlobe')

const require = createRequire(import.meta.url)
const topojson = require(path.join(website, 'node_modules/topojson-client/dist/topojson-client.js'))

const pack = (rings) => {
  const points = rings.reduce((total, ring) => total + ring.length, 0)
  const buffer = Buffer.alloc(12 + (rings.length + 1) * 4 + points * 4)
  buffer.write('NGEO', 0, 'ascii')
  buffer.writeUInt32LE(rings.length, 4)
  buffer.writeUInt32LE(points, 8)

  let offset = 0
  rings.forEach((ring, index) => {
    buffer.writeUInt32LE(offset, 12 + index * 4)
    offset += ring.length
  })
  buffer.writeUInt32LE(offset, 12 + rings.length * 4)

  let at = 12 + (rings.length + 1) * 4
  for (const ring of rings) {
    for (const [ lon, lat ] of ring) {
      buffer.writeInt16LE(Math.max(-32767, Math.min(32767, Math.round(lon / 180 * 32767))), at)
      buffer.writeInt16LE(Math.max(-32767, Math.min(32767, Math.round(lat / 90 * 32767))), at + 2)
      at += 4
    }
  }
  return buffer
}

// fastGlobe.ts's collectionRings: every ring or line of a GeoJSON source, whatever geometry it mixes
const collectionRings = (collection) => {
  const rings = []
  const walk = (geometry) => {
    if (!geometry?.type) return
    if (geometry.type === 'GeometryCollection') return geometry.geometries?.forEach(walk)
    if (!geometry.coordinates) return
    switch (geometry.type) {
      case 'Polygon':
      case 'MultiLineString':
        geometry.coordinates.forEach(ring => rings.push(ring))
        break
      case 'MultiPolygon':
        geometry.coordinates.forEach(polygon => polygon.forEach(ring => rings.push(ring)))
        break
      case 'LineString':
        rings.push(geometry.coordinates)
        break
    }
  }
  if (collection.features) collection.features.forEach(f => walk(f.geometry ?? f))
  else walk(collection)
  return rings
}

const read = (name) => JSON.parse(fs.readFileSync(path.join(assets, name), 'utf8'))

// magneticGraticule.ts's buildParallels: one ring per AACGM parallel, through topojson-client
const magneticLatitudes = () => {
  const topology = read('maglatstopo.json')
  const collection = topojson.feature(topology, topology.objects.topojsondata)
  return collection.features
    .filter(f => Number.isFinite(Number(f.id)))
    .flatMap(f => f.geometry.coordinates)
}

const outputs = {
  'GlobeLand.bin': collectionRings(read('land50.json')),
  'GlobeLakes.bin': collectionRings(read('lakes50.json')),
  // Deliberately the coarse rivers, as the website draws them
  'GlobeRivers.bin': collectionRings(read('rivers110.json')),
  'GlobeMagneticLatitudes.bin': magneticLatitudes()
}

for (const [ name, rings ] of Object.entries(outputs)) {
  const buffer = pack(rings)
  fs.writeFileSync(path.join(out, name), buffer)
  console.log(`${name}: ${rings.length} rings, ${buffer.length} bytes`)
}

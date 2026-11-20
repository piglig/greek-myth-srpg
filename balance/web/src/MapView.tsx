import { ActionIcon, Tooltip } from '@mantine/core'
import { IconFocusCentered, IconNumbers, IconStack2, IconRotate, IconRotateClockwise, IconZoomIn, IconZoomOut } from '@tabler/icons-react'
import { useEffect, useMemo, useRef, useState } from 'react'
import type { Cave, Facing, Team } from './api'

// The map is drawn as an isometric block model: every cell is a column as tall as its height, so
// cliffs, ramps and plateaus read at a glance without decoding numbers. The same view serves the
// editor (sculpt and place), the analysis (heat on the top faces) and the replay (units walk).

export interface MapUnit {
  id: string; name: string; team: Team; pos: [number, number]; size: number; facing?: Facing
  hp?: number; maxHp?: number; alive?: boolean; marked?: boolean; held?: boolean
}
export interface CellEvent { x: number; y: number; buttons: number; button: number; shift: boolean; unit?: string }

interface Props {
  heights: string[]
  terrain?: string[]
  units: MapUnit[]
  selected?: string | null
  actor?: string | null
  ghost?: { unit: MapUnit; pos: [number, number] } | null
  heat?: Record<string, number> | null
  heatColor?: string
  heatUnit?: string
  flagged?: Map<string, 'error' | 'warning'>
  cursor?: string
  tilesOnly?: boolean
  cave?: Partial<Cave> | null // lair entrances and boulders (docs/09 1-5)
  children?: React.ReactNode // overlays placed on the canvas (toolbars, banners)
  onDown?: (e: CellEvent) => void
  onMove?: (e: CellEvent) => void
  onUp?: () => void
}

const TW = 64 // tile width on screen
const TH = 32 // tile height on screen
const HU = 15 // screen pixels per height level
const BASE = 0.7 // slab thickness under height 0, in levels

const TERRAIN: Record<string, { name: string; top: string; left: string; right: string }> = {
  '.': { name: '平地', top: '#93B46F', left: '#7B6549', right: '#5F4D38' },
  f: { name: '森林', top: '#6F9A5B', left: '#7B6549', right: '#5F4D38' },
  w: { name: '浅水', top: '#74BBD8', left: '#4F8EAD', right: '#3E7491' },
  D: { name: '深水', top: '#3F82BD', left: '#2F6596', right: '#254F78' },
  s: { name: '沼泽', top: '#7E8B58', left: '#6A5A43', right: '#524534' },
  b: { name: '燃烧', top: '#D97A3E', left: '#7A4A30', right: '#5E3824' },
  x: { name: '冥河', top: '#6B4E96', left: '#4B3570', right: '#3A2958' },
}
export const TERRAIN_INFO = TERRAIN
export const TEAM_COLOR = { player: '#5B8DEF', enemy: '#E5625E', neutral: '#9AA3B5' }
const GOLD = '#E8B95A'

/** Mixes a hex colour toward white (t > 0) or black (t < 0). */
function shade(hex: string, t: number) {
  const n = parseInt(hex.slice(1), 16)
  const mix = (c: number) => Math.round(t >= 0 ? c + (255 - c) * t : c * (1 + t))
  return `rgb(${mix(n >> 16)},${mix((n >> 8) & 255)},${mix(n & 255)})`
}

/** One character that tells unit types apart: 野狼 → 狼, 巨型野猪 → 猪, 劫掠者弓手 → 弓. */
export const glyph = (name: string) => name.replace(/^(巨型|涅墨亚|劫掠者)/, '').replace(/^野/, '').slice(0, 1) || name.slice(0, 1)

export function MapView(p: Props) {
  const W = p.heights[0]?.length ?? 0
  const D = p.heights.length
  const [rot, setRot] = useState(0)
  const [zoom, setZoom] = useState(1)
  const [pan, setPan] = useState<[number, number]>([0, 0])
  const [numbers, setNumbers] = useState(false)
  const [flat, setFlat] = useState(false) // squash heights: nothing hides behind a cliff
  const hu = flat ? 0 : HU
  const [hover, setHover] = useState<[number, number] | null>(null)
  const svg = useRef<SVGSVGElement>(null)
  const panning = useRef<{ x: number; y: number; pan: [number, number] } | null>(null)
  const h = (x: number, y: number) => (x < 0 || y < 0 || x >= W || y >= D ? -BASE : Number(p.heights[y][x]))
  const t = (x: number, y: number) => p.terrain?.[y]?.[x] ?? '.'

  // Rotated grid coordinates (u, v): the view always looks from the +u/+v corner.
  const toUV = (x: number, y: number): [number, number] =>
    rot === 0 ? [x, y] : rot === 1 ? [D - 1 - y, x] : rot === 2 ? [W - 1 - x, D - 1 - y] : [y, W - 1 - x]
  const fromUV = (u: number, v: number): [number, number] =>
    rot === 0 ? [u, v] : rot === 1 ? [v, D - 1 - u] : rot === 2 ? [W - 1 - u, D - 1 - v] : [W - 1 - v, u]
  /** Screen position of the top (north) corner of a cell's top face. */
  const corner = (u: number, v: number, level: number): [number, number] => [(u - v) * (TW / 2), (u + v) * (TH / 2) - level * hu]
  /** Screen centre of a footprint of `size` cells anchored at (x, y), standing at `level`. */
  const centre = (x: number, y: number, size: number, level: number): [number, number] => {
    let sx = 0
    let sy = 0
    for (const [dx, dy] of [[0, 0], [size - 1, 0], [0, size - 1], [size - 1, size - 1]]) {
      const [u, v] = toUV(x + dx, y + dy)
      const c = corner(u, v, level)
      sx += c[0]
      sy += c[1] + TH / 2
    }
    return [sx / 4, sy / 4]
  }
  const standing = (x: number, y: number, size: number) => {
    let top = 0
    for (let dy = 0; dy < size; dy++) for (let dx = 0; dx < size; dx++) top = Math.max(top, Math.max(0, h(x + dx, y + dy)))
    return top
  }

  const RU = rot % 2 === 0 ? W : D
  const RV = rot % 2 === 0 ? D : W
  const bounds = useMemo(() => {
    const minX = -RV * (TW / 2) - 24
    const maxX = RU * (TW / 2) + 24
    const minY = -5 * HU - 70
    const maxY = (RU + RV) * (TH / 2) + BASE * HU + 24
    return { x: minX, y: minY, w: maxX - minX, h: maxY - minY }
  }, [RU, RV])
  const vb = {
    w: bounds.w / zoom, h: bounds.h / zoom,
    x: bounds.x + (bounds.w - bounds.w / zoom) / 2 - pan[0], y: bounds.y + (bounds.h - bounds.h / zoom) / 2 - pan[1],
  }

  const heatMax = p.heat ? Math.max(1e-9, ...Object.values(p.heat)) : 0

  // Painter's order: cells and units sorted back to front.
  const scene = useMemo(() => {
    type Item = { key: number; node: React.ReactNode }
    const items: Item[] = []
    for (let v = 0; v < RV; v++) {
      for (let u = 0; u < RU; u++) {
        const [x, y] = fromUV(u, v)
        const level = h(x, y)
        const code = t(x, y)
        const col = TERRAIN[code] ?? TERRAIN['.']
        const water = code === 'w' || code === 'D'
        const [sx, sy0] = corner(u, v, level)
        const sy = sy0 + (water ? 4 : 0)
        const top = `${sx},${sy} ${sx + TW / 2},${sy + TH / 2} ${sx},${sy + TH} ${sx - TW / 2},${sy + TH / 2}`
        const [nx1, ny1] = fromUV(u, v + 1)
        const [nx2, ny2] = fromUV(u + 1, v)
        const dropL = (level - h(nx1, ny1)) * hu + (water ? -4 : 0)
        const dropR = (level - h(nx2, ny2)) * hu + (water ? -4 : 0)
        const k = `${x},${y}`
        const heat = p.heat?.[k]
        const flag = p.flagged?.get(k)
        const isHover = hover?.[0] === x && hover?.[1] === y
        const lit = flat ? shade(col.top, 0.3 - level * 0.13) : shade(col.top, Math.min(0.22, level * 0.045))
        const strata = (drop: number) => Array.from({ length: 6 }, (_, i) => (i + 1) * HU).filter((d) => d < drop - 1)
        items.push({
          key: (u + v) * 1000 + u,
          node: (
            <g key={k}>
              {dropL > 0 && <polygon points={`${sx - TW / 2},${sy + TH / 2} ${sx},${sy + TH} ${sx},${sy + TH + dropL} ${sx - TW / 2},${sy + TH / 2 + dropL}`} fill={col.left} stroke={shade(col.left, -0.25)} strokeWidth={0.6} />}
              {dropR > 0 && <polygon points={`${sx},${sy + TH} ${sx + TW / 2},${sy + TH / 2} ${sx + TW / 2},${sy + TH / 2 + dropR} ${sx},${sy + TH + dropR}`} fill={col.right} stroke={shade(col.right, -0.25)} strokeWidth={0.6} />}
              {strata(dropL).map((d) => <line key={`l${d}`} x1={sx - TW / 2} y1={sy + TH / 2 + d} x2={sx} y2={sy + TH + d} stroke="#000" strokeOpacity={0.1} strokeWidth={0.8} />)}
              {strata(dropR).map((d) => <line key={`r${d}`} x1={sx} y1={sy + TH + d} x2={sx + TW / 2} y2={sy + TH / 2 + d} stroke="#000" strokeOpacity={0.12} strokeWidth={0.8} />)}
              <polygon data-c={k} points={top} fill={lit} stroke={shade(col.top, -0.28)} strokeWidth={0.8} strokeLinejoin="round" />
              {code === 'f' && (
                <g pointerEvents="none">
                  <path d={`M${sx - 13} ${sy + TH / 2 + 3} l7 -22 l7 22 z`} fill="#3E6B45" stroke="#2C4F33" strokeWidth={0.8} />
                  <path d={`M${sx + 2} ${sy + TH / 2 + 8} l6 -18 l6 18 z`} fill="#4B7C50" stroke="#2C4F33" strokeWidth={0.8} />
                </g>
              )}
              {water && <path pointerEvents="none" d={`M${sx - 14} ${sy + TH / 2} q5 -4 10 0 t10 0 M${sx - 4} ${sy + TH / 2 + 7} q5 -4 10 0`} fill="none" stroke="#fff" strokeOpacity={0.55} strokeWidth={1.2} />}
              {code === 's' && <g pointerEvents="none" fill="#56633A">{[[-10, 14], [6, 10], [-1, 21], [13, 18]].map(([dx, dy]) => <ellipse key={dx} cx={sx + dx} cy={sy + dy} rx={3.2} ry={1.6} />)}</g>}
              {code === 'b' && <path pointerEvents="none" d={`M${sx} ${sy + TH / 2 + 6} q-9 -8 -2 -18 q1 6 5 5 q-2 -8 4 -12 q-1 8 5 12 q4 7 -3 13 z`} fill="#FFD27A" stroke="#B5451B" strokeWidth={1} />}
              {heat !== undefined && (
                <g pointerEvents="none">
                  <polygon points={top} fill={p.heatColor} fillOpacity={0.3 + Math.sqrt(heat / heatMax) * 0.65} stroke={p.heatColor} strokeWidth={1.2} />
                  {heat / heatMax > 0.12 && <text x={sx} y={sy + TH / 2 + 1} textAnchor="middle" dominantBaseline="central" className="map-heat">{heat >= 10 ? Math.round(heat) : Math.round(heat * 10) / 10}</text>}
                </g>
              )}
              {(numbers || flat) && heat === undefined && <text x={sx} y={sy + TH / 2 + 1} textAnchor="middle" dominantBaseline="central" className="map-num" pointerEvents="none">{level}</text>}
              {flag && <polygon pointerEvents="none" points={top} fill={flag === 'error' ? '#F0616D' : '#F0B429'} fillOpacity={0.35} stroke={flag === 'error' ? '#F0616D' : '#F0B429'} strokeWidth={2.2} strokeDasharray="5 3" />}
              {isHover && <polygon pointerEvents="none" points={top} fill="#fff" fillOpacity={0.28} stroke={GOLD} strokeWidth={2} />}
            </g>
          ),
        })
      }
    }
    const token = (u0: MapUnit, pos: [number, number], opts: { ghost?: boolean; dim?: boolean }) => {
      const level = standing(pos[0], pos[1], u0.size)
      const [cx, cy] = centre(pos[0], pos[1], u0.size, level)
      const big = u0.size > 1
      const r = big ? 21 : 14
      const lift = big ? 46 : 32
      const dead = u0.alive === false
      const color = TEAM_COLOR[u0.team]
      // facing as a wedge on the ground, rotated with the view
      const f = { N: [0, -1], E: [1, 0], S: [0, 1], W: [-1, 0] }[u0.facing ?? 'S']
      const [fu, fv] = rot === 0 ? [f[0], f[1]] : rot === 1 ? [-f[1], f[0]] : rot === 2 ? [-f[0], -f[1]] : [f[1], -f[0]]
      const dx = (fu - fv) * (TW / 2) * 0.42 * u0.size
      const dy = (fu + fv) * (TH / 2) * 0.42 * u0.size
      const sel = p.selected === u0.id || opts.ghost
      const acting = p.actor === u0.id
      const hp = u0.hp !== undefined && u0.maxHp ? Math.max(0, u0.hp / u0.maxHp) : null
      let depth = 0
      for (let ddy = 0; ddy < u0.size; ddy++) for (let ddx = 0; ddx < u0.size; ddx++) { const [u, v] = toUV(pos[0] + ddx, pos[1] + ddy); depth = Math.max(depth, (u + v) * 1000 + u) }
      return {
        key: depth + 0.5,
        node: (
          <g key={opts.ghost ? `ghost-${u0.id}` : `unit-${u0.id}`} data-u={opts.ghost ? undefined : u0.id} opacity={dead ? 0.25 : opts.dim ? 0.4 : opts.ghost ? 0.85 : 1}
            style={{ transform: `translate(${cx}px, ${cy}px)`, transition: opts.ghost ? undefined : 'transform 260ms ease, opacity 200ms' }} pointerEvents={opts.ghost || dead ? 'none' : undefined}>
            <ellipse cx={0} cy={0} rx={r * 1.25} ry={r * 0.62} fill={color} fillOpacity={0.38} stroke={sel ? GOLD : acting ? '#fff' : color} strokeWidth={sel || acting ? 2.4 : 1.4} />
            {!dead && <path d={`M${dx * 1.45} ${dy * 1.45} L${dx * 0.8 - dy * 0.5} ${dy * 0.8 + dx * 0.25} L${dx * 0.8 + dy * 0.5} ${dy * 0.8 - dx * 0.25} z`} fill={color} stroke="#0E1320" strokeWidth={0.8} />}
            <line x1={0} y1={0} x2={0} y2={-lift + r} stroke="#0E1320" strokeWidth={3.4} />
            <line x1={0} y1={0} x2={0} y2={-lift + r} stroke={color} strokeWidth={1.6} />
            <circle cx={0} cy={-lift} r={r} fill={color} stroke={sel ? GOLD : '#0E1320'} strokeWidth={sel ? 3 : 1.8} />
            <circle cx={0} cy={-lift} r={r - 3.2} fill="none" stroke="#fff" strokeOpacity={0.35} strokeWidth={1} />
            <text x={0} y={-lift + 0.5} textAnchor="middle" dominantBaseline="central" className="map-glyph" fontSize={r * 1.02}>{glyph(u0.name)}</text>
            {u0.held && <circle cx={0} cy={-lift} r={r + 4} fill="none" stroke="#fff" strokeWidth={1.6} strokeDasharray="3 3" />}
            {u0.marked && <path d={`M${r - 2} ${-lift - r - 8} l6 10 l-12 0 z`} fill={GOLD} stroke="#0E1320" strokeWidth={1} />}
            {hp !== null && !dead && (
              <g>
                <rect x={-r} y={-lift - r - 9} width={r * 2} height={5} rx={2.5} fill="#0E1320" />
                <rect x={-r + 1} y={-lift - r - 8} width={(r * 2 - 2) * hp} height={3} rx={1.5} fill={hp > 0.5 ? '#4CC38A' : hp > 0.25 ? '#F0B429' : '#F0616D'} />
              </g>
            )}
          </g>
        ),
      }
    }
    for (const e of p.cave?.entrances ?? []) {
      // a lair mouth: the 2x2 area the boss bursts out onto
      const level = standing(e.anchor[0], e.anchor[1], 2)
      const [cx, cy] = centre(e.anchor[0], e.anchor[1], 2, level)
      const [u0, v0] = toUV(e.anchor[0], e.anchor[1])
      const [u1, v1] = toUV(e.anchor[0] + 1, e.anchor[1] + 1)
      const depth = (Math.max(u0, u1) + Math.max(v0, v1)) * 1000 + Math.max(u0, u1) + 0.2
      items.push({
        key: depth,
        node: (
          <g key={`ent-${e.id}`} pointerEvents="none" opacity={e.sealed ? 0.55 : 1}>
            <polygon points={`${cx},${cy - TH} ${cx + TW},${cy} ${cx},${cy + TH} ${cx - TW},${cy}`} fill={e.sealed ? '#000' : GOLD} fillOpacity={e.sealed ? 0.25 : 0.16} stroke={e.sealed ? '#9AA3B5' : GOLD} strokeWidth={2} strokeDasharray="7 5" />
            <path d={`M${cx - 15} ${cy + 6} v-12 a15 15 0 0 1 30 0 v12 z`} fill="#0E1320" stroke={e.sealed ? '#9AA3B5' : GOLD} strokeWidth={1.8} />
            {e.sealed && <path d={`M${cx - 9} ${cy - 12} l18 16 M${cx + 9} ${cy - 12} l-18 16`} stroke="#F0616D" strokeWidth={2.5} strokeLinecap="round" />}
          </g>
        ),
      })
    }
    for (const b of p.cave?.boulders ?? []) {
      if (b.placed) continue
      const level = Math.max(0, h(b.pos[0], b.pos[1]))
      const [cx, cy] = centre(b.pos[0], b.pos[1], 1, level)
      const [u, v] = toUV(b.pos[0], b.pos[1])
      items.push({
        key: (u + v) * 1000 + u + 0.4,
        node: (
          <g key={`boulder-${b.id}`} pointerEvents="none">
            <ellipse cx={cx} cy={cy + 2} rx={21} ry={10} fill="#000" fillOpacity={0.28} />
            <path d={`M${cx - 19} ${cy} q-2 -22 12 -27 q16 -5 24 9 q6 12 -4 20 q-16 9 -32 -2 z`} fill="#9A9AA6" stroke="#3B3F4D" strokeWidth={1.6} />
            <path d={`M${cx - 8} ${cy - 20} q9 -5 17 1`} fill="none" stroke="#fff" strokeOpacity={0.5} strokeWidth={2} strokeLinecap="round" />
            {(b.progress ?? 0) > 0 && <text x={cx} y={cy - 7} textAnchor="middle" className="map-num" style={{ fill: '#0E1320' }}>{b.progress}/2</text>}
          </g>
        ),
      })
    }
    for (const u of p.units) items.push(token(u, u.pos, { dim: p.ghost?.unit.id === u.id }))
    if (p.ghost) items.push(token(p.ghost.unit, p.ghost.pos, { ghost: true }))
    return items.sort((a, b) => a.key - b.key).map((i) => i.node)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [p.heights, p.terrain, p.units, p.selected, p.actor, p.ghost, p.heat, p.heatColor, p.flagged, p.cave, rot, hover, numbers, flat])

  const hit = (e: React.PointerEvent): CellEvent | null => {
    // With `tilesOnly` (painting, or dragging a unit) look through unit pins to the tile under the cursor.
    const stack = document.elementsFromPoint(e.clientX, e.clientY)
    const el = p.tilesOnly ? stack.find((x) => (x as HTMLElement).dataset?.c !== undefined) : stack[0]
    const unitEl = p.tilesOnly ? null : (el?.closest?.('[data-u]') as HTMLElement | null)
    const base = { buttons: e.buttons, button: e.button, shift: e.shiftKey }
    if (unitEl) {
      const u = p.units.find((x) => x.id === unitEl.dataset.u)
      if (u) return { x: u.pos[0], y: u.pos[1], unit: u.id, ...base }
    }
    const cellEl = el?.closest?.('[data-c]') as HTMLElement | null
    if (!cellEl) return null
    const [x, y] = cellEl.dataset.c!.split(',').map(Number)
    return { x, y, ...base }
  }

  // Test and automation hook: where a cell is on screen.
  useEffect(() => {
    ;(window as any).__studioMap = {
      cellToScreen: (x: number, y: number) => {
        const el = svg.current
        if (!el) return null
        const [cx, cy] = centre(x, y, 1, Math.max(0, h(x, y)))
        const pt = el.createSVGPoint()
        pt.x = cx
        pt.y = cy
        const s = pt.matrixTransform(el.getScreenCTM()!)
        return [s.x, s.y]
      },
    }
  })

  const onWheel = (e: React.WheelEvent) => setZoom((z) => Math.min(3, Math.max(0.6, z * (e.deltaY < 0 ? 1.12 : 0.89))))
  if (!W || !D) return null
  const hoverHeat = hover && p.heat ? p.heat[`${hover[0]},${hover[1]}`] : undefined
  return (
    <div className="canvas">
      <svg
        ref={svg} className="map-svg" viewBox={`${vb.x} ${vb.y} ${vb.w} ${vb.h}`} style={{ cursor: p.cursor ?? 'default' }}
        onWheel={onWheel}
        onPointerDown={(e) => {
          e.preventDefault()
          ;(document.activeElement as HTMLElement | null)?.blur?.()
          ;(e.currentTarget as Element).setPointerCapture?.(e.pointerId)
          if (e.button === 1) { panning.current = { x: e.clientX, y: e.clientY, pan }; return }
          const c = hit(e)
          if (c) p.onDown?.(c)
          else if (e.button === 0) panning.current = { x: e.clientX, y: e.clientY, pan }
        }}
        onPointerMove={(e) => {
          if (panning.current) {
            const k = vb.w / (svg.current?.clientWidth || 1)
            setPan([panning.current.pan[0] + (e.clientX - panning.current.x) * k, panning.current.pan[1] + (e.clientY - panning.current.y) * k])
            return
          }
          const c = hit(e)
          const next: [number, number] | null = c ? [c.x, c.y] : null
          if (next?.[0] !== hover?.[0] || next?.[1] !== hover?.[1]) setHover(next)
          if (c) p.onMove?.(c)
        }}
        onPointerUp={() => { if (panning.current) panning.current = null; else p.onUp?.() }}
        onPointerLeave={() => setHover(null)}
        onContextMenu={(e) => e.preventDefault()}
      >
        <defs>
          <radialGradient id="floor" cx="50%" cy="50%" r="50%"><stop offset="0%" stopColor="#26304A" /><stop offset="100%" stopColor="#26304A" stopOpacity={0} /></radialGradient>
        </defs>
        <ellipse cx={(RU - RV) * (TW / 4)} cy={(RU + RV) * (TH / 4) + 30} rx={(RU + RV) * (TW / 2) * 0.62} ry={(RU + RV) * (TH / 2) * 0.72} fill="url(#floor)" pointerEvents="none" />
        {scene}
      </svg>

      {p.children}

      <div className="view-ctl">
        <Tooltip label="向左转 90°"><ActionIcon variant="subtle" color="gray" aria-label="向左转" onClick={() => setRot((r) => (r + 3) % 4)}><IconRotate size={17} /></ActionIcon></Tooltip>
        <Tooltip label="向右转 90°"><ActionIcon variant="subtle" color="gray" aria-label="向右转" onClick={() => setRot((r) => (r + 1) % 4)}><IconRotateClockwise size={17} /></ActionIcon></Tooltip>
        <span className="sep" />
        <Tooltip label="缩小"><ActionIcon variant="subtle" color="gray" aria-label="缩小" onClick={() => setZoom((z) => Math.max(0.6, z / 1.2))}><IconZoomOut size={17} /></ActionIcon></Tooltip>
        <Tooltip label="放大（也可以滚轮）"><ActionIcon variant="subtle" color="gray" aria-label="放大" onClick={() => setZoom((z) => Math.min(3, z * 1.2))}><IconZoomIn size={17} /></ActionIcon></Tooltip>
        <Tooltip label="回到全图"><ActionIcon variant="subtle" color="gray" aria-label="回到全图" onClick={() => { setZoom(1); setPan([0, 0]) }}><IconFocusCentered size={17} /></ActionIcon></Tooltip>
        <span className="sep" />
        <Tooltip label={flat ? '恢复立体' : '压平：高度改用深浅和数字表示，不会互相遮挡'}><ActionIcon variant={flat ? 'filled' : 'subtle'} color={flat ? 'gold' : 'gray'} aria-label="压平视图" onClick={() => setFlat(!flat)}><IconStack2 size={17} /></ActionIcon></Tooltip>
        <Tooltip label="在每格上显示高度数字"><ActionIcon variant={numbers ? 'filled' : 'subtle'} color={numbers ? 'gold' : 'gray'} aria-label="显示高度数字" onClick={() => setNumbers(!numbers)}><IconNumbers size={17} /></ActionIcon></Tooltip>
      </div>

      <div className="readout">
        {hover ? (
          <>
            <b className="mono">{hover[0]}, {hover[1]}</b>
            <span>高度 {Math.max(0, h(hover[0], hover[1]))}</span>
            <span>{TERRAIN[t(hover[0], hover[1])]?.name}</span>
            {hoverHeat !== undefined && <span className="hot">{p.heatUnit} {hoverHeat}</span>}
          </>
        ) : <span className="dim">{W} × {D} 格 · 拖动空白处平移，滚轮缩放</span>}
      </div>
    </div>
  )
}

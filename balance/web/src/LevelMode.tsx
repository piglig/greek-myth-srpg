import { ActionIcon, Button, NumberInput, SegmentedControl, Select, TextInput, Textarea, Tooltip } from '@mantine/core'
import { IconAlertTriangle, IconArrowBackUp, IconArrowForwardUp, IconCircleCheck, IconCircleX, IconCube, IconEraser, IconMountain, IconPointer, IconTrees, IconUserPlus } from '@tabler/icons-react'
import { useEffect, useMemo, useRef, useState } from 'react'
import { api, type Battle, type BattleUnit, type Facing, type StudioData } from './api'
import { fail } from './App'
import { glyph, MapView, TEAM_COLOR, TERRAIN_INFO, type CellEvent, type MapUnit } from './MapView'
import { isBaseline, useStore, type Tool } from './store'

export function toMapUnits(battle: Battle, units: Record<string, any>): MapUnit[] {
  return battle.units.map((u) => ({
    id: u.id, name: units[u.def]?.name ?? u.def, team: u.team, pos: u.pos, size: units[u.def]?.size ?? 1, facing: u.facing ?? 'S',
  }))
}

function unitAt(battle: Battle, units: Record<string, any>, x: number, y: number): BattleUnit | undefined {
  return battle.units.find((u) => {
    const size = units[u.def]?.size ?? 1
    return x >= u.pos[0] && x < u.pos[0] + size && y >= u.pos[1] && y < u.pos[1] + size
  })
}

const setChar = (rows: string[], x: number, y: number, ch: string) =>
  rows.map((r, i) => (i === y ? r.slice(0, x) + ch + r.slice(x + 1) : r))

function nextId(battle: Battle, def: string) {
  for (let i = 1; ; i++) {
    const id = `${def}_${i}`
    if (!battle.units.some((u) => u.id === id)) return id
  }
}

const TOOLS: { id: Tool; label: string; icon: typeof IconPointer; key: string }[] = [
  { id: 'select', label: '选择', icon: IconPointer, key: 'V' },
  { id: 'height', label: '高度', icon: IconMountain, key: 'H' },
  { id: 'terrain', label: '地形', icon: IconTrees, key: 'T' },
  { id: 'unit', label: '单位', icon: IconUserPlus, key: 'U' },
  { id: 'erase', label: '移除', icon: IconEraser, key: 'E' },
]
const KEY_TOOL: Record<string, Tool> = { v: 'select', h: 'height', t: 'terrain', u: 'unit', e: 'erase' }
const NEXT_FACING: Record<Facing, Facing> = { N: 'E', E: 'S', S: 'W', W: 'N' }
const STAT_LABEL: [string, string][] = [['hp', '生命'], ['str', '力量'], ['def', '防御'], ['move', '移动']]

/** The tool dock floating over the canvas, with the active tool's options above it. */
function Dock({ data }: { data: StudioData }) {
  const s = useStore()
  return (
    <div className="dock-wrap">
      {s.tool === 'height' && (
        <div className="options">
          <button className="chip" aria-pressed={s.brushHeight < 0} onClick={() => s.set({ brushHeight: -1 })}>雕刻</button>
          <span className="hint">或直接设为</span>
          {[0, 1, 2, 3, 4, 5].map((i) => <button key={i} className="chip num" aria-pressed={s.brushHeight === i} onClick={() => s.set({ brushHeight: i })}>{i}</button>)}
          <span className="hint">{s.brushHeight < 0 ? '左键抬高一层，右键或 Shift 降低；按住拖动把经过的格子抹成同一高度' : '点击或拖动，把格子设为这个高度'}</span>
        </div>
      )}
      {s.tool === 'terrain' && (
        <div className="options">
          {Object.entries(TERRAIN_INFO).map(([code, t]) => (
            <button key={code} className="chip" aria-pressed={s.brushTerrain === code} onClick={() => s.set({ brushTerrain: code })}><i style={{ background: t.top }} />{t.name}</button>
          ))}
        </div>
      )}
      {s.tool === 'unit' && (
        <div className="options">
          <SegmentedControl size="xs" value={s.placeTeam} onChange={(v) => s.set({ placeTeam: v as 'player' | 'enemy' })} data={[{ value: 'enemy', label: '敌方' }, { value: 'player', label: '我方' }]} />
          <span className="sep" style={{ width: 1, height: 20, background: 'var(--line-strong)' }} />
          {Object.entries(data.units).map(([id, u]) => (
            <button key={id} className="chip" aria-pressed={s.placeDef === id} onClick={() => s.set({ placeDef: id })} title={`生命 ${u.hp} · 力量 ${u.str} · 防御 ${u.def}${(u.size ?? 1) > 1 ? ` · 占 ${u.size}×${u.size} 格` : ''}`}>
              <span className="pawn" style={{ background: TEAM_COLOR[s.placeTeam] }}>{glyph(u.name)}</span>{u.name}
            </button>
          ))}
        </div>
      )}
      {s.tool === 'select' && s.selectedUnit && <div className="options"><span className="hint">拖动移动 · R 转向 · Delete 移除</span></div>}
      <div className="dock">
        {TOOLS.map((t) => (
          <button key={t.id} className="tool" aria-pressed={s.tool === t.id} onClick={() => s.set({ tool: t.id })}>
            <t.icon size={19} stroke={1.7} />{t.label}<kbd>{t.key}</kbd>
          </button>
        ))}
        <span className="sep" />
        <Tooltip label="撤销（Ctrl+Z）"><ActionIcon size="lg" variant="subtle" color="gray" disabled={s.past.length === 0} onClick={s.undo} aria-label="撤销"><IconArrowBackUp size={19} /></ActionIcon></Tooltip>
        <Tooltip label="重做（Ctrl+Y）"><ActionIcon size="lg" variant="subtle" color="gray" disabled={s.future.length === 0} onClick={s.redo} aria-label="重做"><IconArrowForwardUp size={19} /></ActionIcon></Tooltip>
      </div>
    </div>
  )
}

export function LevelMode({ data, onNewVariant }: { data: StudioData; onNewVariant: () => void }) {
  const s = useStore()
  const locked = isBaseline(s.variant)
  const draft = s.draft!
  // While a brush stroke or a drag is in progress we render `working`; it becomes one undo step on release.
  const [working, setWorking] = useState<Battle | null>(null)
  const [drag, setDrag] = useState<{ id: string; pos: [number, number] } | null>(null)
  const stroke = useRef<{ level: string } | null>(null)
  const battle = working ?? draft
  const units = data.units
  const [preview, setPreview] = useState<{ url?: string; busy: boolean }>({ busy: false })
  useEffect(() => setPreview({ busy: false }), [s.battleId, s.variant])

  const issues = data.issues.filter((i) => i.where === `battles/${draft.id}` || !i.where.startsWith('battles/'))
  const flagged = useMemo(() => {
    const m = new Map<string, 'error' | 'warning'>()
    for (const i of issues) for (const c of i.cells ?? []) if (m.get(`${c[0]},${c[1]}`) !== 'error') m.set(`${c[0]},${c[1]}`, i.level)
    return m
  }, [issues])

  const paint = (b: Battle, x: number, y: number): Battle => {
    if (s.tool === 'height') return { ...b, heights: setChar(b.heights, x, y, stroke.current!.level) }
    const terrain = b.terrain?.length ? b.terrain : b.heights.map((r) => '.'.repeat(r.length))
    return { ...b, terrain: setChar(terrain, x, y, s.brushTerrain) }
  }

  const onDown = (e: CellEvent) => {
    if (locked) return
    const hit = e.unit ? draft.units.find((u) => u.id === e.unit) : unitAt(draft, units, e.x, e.y)
    if (s.tool === 'select') {
      s.set({ selectedUnit: hit?.id ?? null })
      if (hit && e.button === 0) setDrag({ id: hit.id, pos: hit.pos })
    } else if (s.tool === 'height' || s.tool === 'terrain') {
      const now = Number(draft.heights[e.y][e.x])
      const lower = e.button === 2 || e.shift
      const level = s.brushHeight >= 0 ? s.brushHeight : Math.min(5, Math.max(0, now + (lower ? -1 : 1)))
      stroke.current = { level: String(level) }
      setWorking(paint(draft, e.x, e.y))
    } else if (s.tool === 'unit') {
      if (hit) { s.set({ selectedUnit: hit.id, tool: 'select' }); return }
      const id = s.placeDef === 'hero' && !draft.units.some((u) => u.id === 'hero') ? 'hero' : nextId(draft, s.placeDef)
      s.edit({ ...draft, units: [...draft.units, { def: s.placeDef, id, team: s.placeTeam, pos: [e.x, e.y], facing: s.placeTeam === 'enemy' ? 'S' : 'N' }] })
      s.set({ selectedUnit: id })
    } else if (s.tool === 'erase' && hit) {
      s.edit({ ...draft, units: draft.units.filter((u) => u.id !== hit.id) })
    }
  }
  const onMove = (e: CellEvent) => {
    if (stroke.current && working && e.buttons && !e.unit) setWorking(paint(working, e.x, e.y))
    else if (drag && e.buttons && e.unit !== drag.id) setDrag({ id: drag.id, pos: [e.x, e.y] })
  }
  const onUp = () => {
    if (stroke.current && working) s.edit(working)
    if (drag) {
      const u = draft.units.find((x) => x.id === drag.id)
      if (u && (u.pos[0] !== drag.pos[0] || u.pos[1] !== drag.pos[1])) {
        s.edit({ ...draft, units: draft.units.map((x) => (x.id === drag.id ? { ...x, pos: drag.pos } : x)) })
      }
    }
    stroke.current = null
    setWorking(null)
    setDrag(null)
  }

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const el = e.target as HTMLElement
      if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.isContentEditable) return
      const st = useStore.getState()
      if (isBaseline(st.variant) || st.mode !== 'level' || !st.draft) return
      const k = e.key.toLowerCase()
      if ((e.ctrlKey || e.metaKey) && k === 'z') { e.preventDefault(); e.shiftKey ? st.redo() : st.undo() }
      else if ((e.ctrlKey || e.metaKey) && k === 'y') { e.preventDefault(); st.redo() }
      else if (e.ctrlKey || e.metaKey || e.altKey) return
      else if ((k === 'delete' || k === 'backspace') && st.selectedUnit) {
        st.edit({ ...st.draft, units: st.draft.units.filter((u) => u.id !== st.selectedUnit) })
        st.set({ selectedUnit: null })
      } else if (k === 'r' && st.selectedUnit) {
        st.edit({ ...st.draft, units: st.draft.units.map((u) => (u.id === st.selectedUnit ? { ...u, facing: NEXT_FACING[u.facing ?? 'S'] } : u)) })
      } else if (st.tool === 'height' && /^[0-5]$/.test(k)) st.set({ brushHeight: Number(k) })
      else if (k === 'escape') st.set({ selectedUnit: null, tool: 'select' })
      else if (KEY_TOOL[k]) st.set({ tool: KEY_TOOL[k] })
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [])

  const mapUnits = toMapUnits(battle, units)
  const dragged = drag && mapUnits.find((u) => u.id === drag.id)
  const sel = draft.units.find((u) => u.id === s.selectedUnit)
  const selDef = sel ? units[sel.def] : null
  const patchUnit = (patch: Partial<BattleUnit>) => {
    if (!sel) return
    s.edit({ ...draft, units: draft.units.map((u) => (u.id === sel.id ? { ...u, ...patch } : u)) })
    if (patch.id) s.set({ selectedUnit: patch.id })
  }
  const W = draft.heights[0].length
  const D = draft.heights.length
  const resize = (w: number, d: number) => {
    const fit = (rows: string[] | undefined, fill: string) =>
      Array.from({ length: d }, (_, y) => ((rows?.[y] ?? '') + fill.repeat(w)).slice(0, w))
    s.edit({ ...draft, heights: fit(draft.heights, '0'), terrain: fit(draft.terrain, '.') })
  }
  const makePreview = async () => {
    setPreview({ busy: true })
    try { setPreview({ busy: false, url: (await api.preview(draft.id, s.variant)).url }) } catch (e) { setPreview({ busy: false }); fail(e) }
  }
  const cursor = locked ? 'default' : s.tool === 'select' ? (drag ? 'grabbing' : 'default') : 'crosshair'
  const players = draft.units.filter((u) => u.team === 'player').length
  const enemies = draft.units.filter((u) => u.team === 'enemy').length

  return (
    <>
      <main className="stage">
        <MapView
          cave={battle.cave} heights={battle.heights} terrain={battle.terrain} units={mapUnits} selected={s.selectedUnit} flagged={flagged} cursor={cursor}
          tilesOnly={!!drag || s.tool === 'height' || s.tool === 'terrain' || s.tool === 'unit'}
          ghost={dragged && drag ? { unit: dragged, pos: drag.pos } : null}
          onDown={onDown} onMove={onMove} onUp={onUp}
        >
          <div className="hud-top">
            <div className="hud-title">
              <h1>{draft.title}</h1>
              <p><span className="mono">{draft.id}</span>·<span>{W} × {D} 格</span>·<span style={{ color: TEAM_COLOR.player }}>我方 {players}</span><span style={{ color: TEAM_COLOR.enemy }}>敌方 {enemies}</span></p>
            </div>
          </div>
          {locked && (
            <div className="hud-notes">
              <div className="note">
                <span className="grow">基线是正式数据，这里只能看。新建一个变体就能开始改，采用之前不会影响正式数据。</span>
                <Button size="xs" onClick={onNewVariant}>新建变体</Button>
              </div>
            </div>
          )}
          {!locked && <Dock data={data} />}
        </MapView>
      </main>

      <aside className="side">
        <div className="section">
          <h3>检查{issues.length > 0 && <span className="count">{issues.length} 项</span>}</h3>
          {issues.length === 0 ? <div className="ok-line"><IconCircleCheck size={17} />没有问题，可以去模拟。</div> : issues.map((i, n) => (
            <div key={n} className={`issue ${i.level}`}>
              {i.level === 'error' ? <IconCircleX size={17} /> : <IconAlertTriangle size={17} />}
              <span>{i.message}{!i.where.startsWith('battles/') && <span className="muted">（数值表 {i.where}）</span>}</span>
            </div>
          ))}
        </div>

        {sel ? (
          <div className="section">
            <h3>选中的单位</h3>
            <div className="unit-head">
              <span className="pawn" style={{ background: TEAM_COLOR[sel.team] }}>{glyph(selDef?.name ?? sel.def)}</span>
              <div><b>{selDef?.name ?? sel.def}</b><small>{sel.id} · ({sel.pos[0]}, {sel.pos[1]})</small></div>
            </div>
            {selDef && <div className="stats">{STAT_LABEL.map(([k, label]) => <div key={k}><b>{selDef[k] ?? '—'}</b><small>{label}</small></div>)}</div>}
            <div className="fieldgrid">
              <Select size="xs" label="类型" allowDeselect={false} disabled={locked} value={sel.def} data={Object.entries(units).map(([id, u]) => ({ value: id, label: u.name }))} onChange={(v) => v && patchUnit({ def: v })} />
              <TextInput size="xs" label="编号" key={sel.id} defaultValue={sel.id} disabled={locked}
                onBlur={(e) => { const v = e.currentTarget.value.trim(); if (v && v !== sel.id && /^[A-Za-z0-9_]+$/.test(v)) patchUnit({ id: v }) }} />
              <div>
                <div style={{ fontSize: 12, fontWeight: 500, marginBottom: 5 }}>阵营</div>
                <SegmentedControl fullWidth size="xs" disabled={locked} value={sel.team} onChange={(v) => patchUnit({ team: v as BattleUnit['team'] })} data={[{ value: 'player', label: '我方' }, { value: 'enemy', label: '敌方' }, { value: 'neutral', label: '中立' }]} />
              </div>
              <div>
                <div style={{ fontSize: 12, fontWeight: 500, marginBottom: 5 }}>朝向</div>
                <SegmentedControl fullWidth size="xs" disabled={locked} value={sel.facing ?? 'S'} onChange={(v) => patchUnit({ facing: v as Facing })} data={[{ value: 'N', label: '北' }, { value: 'E', label: '东' }, { value: 'S', label: '南' }, { value: 'W', label: '西' }]} />
              </div>
              {!locked && <Button size="xs" variant="light" color="red" onClick={() => { s.edit({ ...draft, units: draft.units.filter((u) => u.id !== sel.id) }); s.set({ selectedUnit: null }) }}>移除这个单位</Button>}
            </div>
          </div>
        ) : (
          <div className="section">
            <h3>关卡</h3>
            <div className="fieldgrid">
              <TextInput size="xs" label="名称" key={`t${s.draftKey}`} defaultValue={draft.title} disabled={locked} onBlur={(e) => e.currentTarget.value.trim() && s.edit({ ...draft, title: e.currentTarget.value.trim() })} />
              <div className="two">
                <NumberInput size="xs" label="宽（格）" disabled={locked} min={4} max={24} value={W} onChange={(v) => Number(v) >= 4 && resize(Number(v), D)} />
                <NumberInput size="xs" label="深（格）" disabled={locked} min={4} max={24} value={D} onChange={(v) => Number(v) >= 4 && resize(W, Number(v))} />
              </div>
              <Textarea size="xs" label="设计备注" autosize minRows={2} maxRows={7} key={`n${s.draftKey}`} defaultValue={draft.note ?? ''} disabled={locked} onBlur={(e) => s.edit({ ...draft, note: e.currentTarget.value })} />
            </div>
          </div>
        )}

        {draft.cave && (
          <div className="section">
            <h3>洞穴<span className="count">Boss：{units[draft.units.find((u) => u.id === draft.cave!.boss)?.def ?? '']?.name ?? draft.cave.boss}</span></h3>
            <div className="fieldgrid">
              <NumberInput size="xs" label="Boss 生命降到多少时退入洞内" disabled={locked} min={1} value={draft.cave.trigger_hp}
                onChange={(v) => Number(v) > 0 && s.edit({ ...draft, cave: { ...draft.cave!, trigger_hp: Number(v) } })} />
              {draft.cave.entrances.map((e, i) => (
                <div className="two" key={e.id}>
                  <NumberInput size="xs" label={`入口 ${e.id} · X`} disabled={locked} min={0} max={W - 2} value={e.anchor[0]}
                    onChange={(v) => s.edit({ ...draft, cave: { ...draft.cave!, entrances: draft.cave!.entrances.map((x, j) => (j === i ? { ...x, anchor: [Number(v) || 0, x.anchor[1]] } : x)) } })} />
                  <NumberInput size="xs" label="Y" disabled={locked} min={0} max={D - 2} value={e.anchor[1]}
                    onChange={(v) => s.edit({ ...draft, cave: { ...draft.cave!, entrances: draft.cave!.entrances.map((x, j) => (j === i ? { ...x, anchor: [x.anchor[0], Number(v) || 0] } : x)) } })} />
                </div>
              ))}
              {(draft.cave.boulders ?? []).map((b, i) => (
                <div className="two" key={b.id}>
                  <NumberInput size="xs" label={`巨石（封 ${b.seals}）· X`} disabled={locked} min={0} max={W - 1} value={b.pos[0]}
                    onChange={(v) => s.edit({ ...draft, cave: { ...draft.cave!, boulders: draft.cave!.boulders!.map((x, j) => (j === i ? { ...x, pos: [Number(v) || 0, x.pos[1]] } : x)) } })} />
                  <NumberInput size="xs" label="Y" disabled={locked} min={0} max={D - 1} value={b.pos[1]}
                    onChange={(v) => s.edit({ ...draft, cave: { ...draft.cave!, boulders: draft.cave!.boulders!.map((x, j) => (j === i ? { ...x, pos: [x.pos[0], Number(v) || 0] } : x)) } })} />
                </div>
              ))}
              <p className="empty">金色虚线框是 Boss 冲出的位置；灰色石头推两次（赫拉克勒斯一次）就封住对应入口。</p>
            </div>
          </div>
        )}

        {!locked && (
          <div className="section">
            <h3>相对基线的改动</h3>
            {data.diff.length === 0 ? <p className="empty">还没有改动。</p> : (
              <ul className="difflist">
                {data.diff.map((f) => [<li key={f.file} className="file">{f.file}</li>, ...f.lines.map((l, i) => <li key={f.file + i}>{l}</li>)])}
              </ul>
            )}
          </div>
        )}

        <div className="section">
          <h3>游戏内效果</h3>
          <Button size="xs" variant="default" fullWidth leftSection={<IconCube size={15} />} loading={preview.busy} onClick={makePreview}>用游戏引擎渲染</Button>
          {preview.busy && <p className="empty" style={{ marginTop: 8 }}>会短暂弹出一个游戏窗口，约 5 秒。</p>}
          {preview.url && <a href={preview.url} target="_blank" rel="noreferrer"><img className="preview-img" src={preview.url} alt={`${draft.title} 的游戏内画面`} /></a>}
        </div>
      </aside>
    </>
  )
}

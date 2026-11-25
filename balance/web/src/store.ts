import { create } from 'zustand'
import type { Battle } from './api'

export type Mode = 'level' | 'tables' | 'sim' | 'replay' | 'compare' | 'difficulty' | 'supports'
export type Tool = 'select' | 'height' | 'terrain' | 'unit' | 'erase'
export type HeatLayer = 'none' | 'kills' | 'falls' | 'dmg'

interface State {
  mode: Mode
  variant: string
  battleId: string
  tool: Tool
  brushHeight: number
  brushTerrain: string
  placeDef: string
  placeTeam: 'player' | 'enemy'
  selectedUnit: string | null
  heat: HeatLayer
  bot: string
  replaySeed: number | null
  // The battle being edited: a local copy that autosaves into the variant.
  draft: Battle | null
  draftKey: string // `${variant}/${battleId}` the draft belongs to
  dirty: boolean
  past: Battle[]
  future: Battle[]
  set: (patch: Partial<State>) => void
  loadDraft: (key: string, battle: Battle) => void
  edit: (next: Battle) => void
  undo: () => void
  redo: () => void
  markSaved: () => void
}

// Deep links: ?mode=sim&variant=x&battle=1-4&heat=kills&bot=novice&seed=3 opens that exact view,
// so a person or the AI can hand over a link to what they are looking at.
const url = new URLSearchParams(window.location.search)
const MODES: Mode[] = ['level', 'tables', 'sim', 'replay', 'compare', 'difficulty', 'supports']

export const useStore = create<State>((set, get) => ({
  mode: MODES.includes(url.get('mode') as Mode) ? (url.get('mode') as Mode) : 'level',
  variant: url.get('variant') || 'baseline',
  battleId: url.get('battle') || '',
  tool: 'select',
  brushHeight: -1, // -1 = sculpt (click raises, right-click lowers); 0-5 = set to that height
  brushTerrain: 'f',
  placeDef: 'wolf',
  placeTeam: 'enemy',
  selectedUnit: null,
  heat: (['kills', 'falls', 'dmg'].includes(url.get('heat') ?? '') ? url.get('heat') : 'none') as HeatLayer,
  bot: url.get('bot') || 'casual',
  replaySeed: url.get('seed') !== null ? Number(url.get('seed')) : null,
  draft: null,
  draftKey: '',
  dirty: false,
  past: [],
  future: [],
  set: (patch) => set(patch),
  loadDraft: (key, battle) => set({ draft: battle, draftKey: key, dirty: false, past: [], future: [], selectedUnit: null }),
  edit: (next) => {
    const { draft, past } = get()
    if (!draft || JSON.stringify(draft) === JSON.stringify(next)) return
    set({ draft: next, past: [...past.slice(-60), draft], future: [], dirty: true })
  },
  undo: () => {
    const { draft, past, future } = get()
    if (!draft || past.length === 0) return
    set({ draft: past[past.length - 1], past: past.slice(0, -1), future: [draft, ...future], dirty: true })
  },
  redo: () => {
    const { draft, past, future } = get()
    if (!draft || future.length === 0) return
    set({ draft: future[0], past: [...past, draft], future: future.slice(1), dirty: true })
  },
  markSaved: () => set({ dirty: false }),
}))

export const isBaseline = (variant: string) => variant === 'baseline'

useStore.subscribe((s) => {
  const q = new URLSearchParams()
  q.set('mode', s.mode)
  if (s.battleId) q.set('battle', s.battleId)
  if (s.variant !== 'baseline') q.set('variant', s.variant)
  if (s.mode === 'sim' && s.heat !== 'none') q.set('heat', s.heat)
  if (s.mode === 'sim' || s.mode === 'replay') q.set('bot', s.bot)
  if (s.mode === 'replay' && s.replaySeed !== null) q.set('seed', String(s.replaySeed))
  const next = `${window.location.pathname}?${q}`
  if (next !== window.location.pathname + window.location.search) window.history.replaceState(null, '', next)
})

;(window as any).__studio = useStore

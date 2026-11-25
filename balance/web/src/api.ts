// Typed client for the Balance Studio API (engine/studio/server.go).

export type Team = 'player' | 'enemy' | 'neutral'
export type Facing = 'N' | 'E' | 'S' | 'W'

export interface BattleUnit { def: string; id: string; team: Team; pos: [number, number]; facing?: Facing }
export interface Battle {
  id: string; title: string; order?: number; note?: string
  heights: string[]; terrain?: string[]; units: BattleUnit[]
  cave?: Cave
}
export interface Cave {
  boss: string; trigger_hp: number; emerge_actions?: number
  entrances: { id: string; anchor: [number, number]; sealed?: boolean }[]
  boulders?: { id: string; pos: [number, number]; seals?: string; placed?: boolean; progress?: number }[]
}
export interface Issue { level: 'error' | 'warning'; where: string; message: string; unit?: string; cells?: [number, number][]; path?: string }
export interface DiffFile { file: string; lines: string[] }
export interface StudioData {
  variant: string
  units: Record<string, any>
  skills: Record<string, any>
  skill_tree: any
  battles: Record<string, Battle>
  issues: Issue[]
  diff: DiffFile[]
  hashes: Record<string, string>
}
export interface Variant { name: string; note: string; created: string; updated: string; by: string; changed: string[] }
export interface Verdict {
  bot: string; metric: string; label: string; pct: boolean; target: [number, number] | null
  value: number | null; lo: number | null; hi: number | null; n: number; status: string; note: string
}
export interface BotResult {
  label: string
  status: 'none' | 'fresh' | 'stale' | 'unknown'
  meta?: { runs: number; seed: number; finished: string; by: string } | null
  runs?: number
  outcomes?: { key: string; label: string; count: number; share: number; lo: number; hi: number }[]
  rounds?: { rounds: number; win: number; loss: number }[]
  hp?: { from: number; to: number; count: number }[]
  damage?: { def: string; name: string; dealt: number; taken: number; share: number }[]
  sources?: { key: string; label: string; per_battle: number; share: number }[]
  mechanics?: { key: string; label: string; battles: number; per_battle: number }[]
  heat?: { kills: Record<string, number>; falls: Record<string, number>; dmg: Record<string, number> }
  table?: { seed: number; result: string; rounds: number; hp: number; falls: number }[]
}
export interface Results {
  battle: string; variant: string; hash: string
  bots: Record<string, BotResult>
  verdicts: Verdict[]
  targets: any
  runs_min: number
}
export interface Job {
  id: number; battle: string; variant: string; bots: string[]; runs: number; seed: number; actor: string
  status: 'queued' | 'running' | 'done' | 'failed' | 'cancelled'; done: number; total: number; error: string; elapsed: number
}
export interface Activity { ts: string; actor: 'human' | 'ai'; kind: string; text: string; variant?: string; battle?: string }
export interface ReplayUnit {
  def: string; name: string; team: Team; pos: [number, number]; size: number; hp: number; max_hp: number
  facing: Facing; alive: boolean; hidden?: boolean; statuses: string[]; grappled_by: string; escape: number; stagger: number; stagger_max: number
}
export interface ReplayFrame { round: number; actor: string; lines: string[]; units: Record<string, ReplayUnit>; cave?: Partial<Cave> }
export interface Replay { battle: string; bot: string; seed: number; result: string; rounds: number; frames: ReplayFrame[] }
export interface Meta {
  terrain: Record<string, string>; bots: Record<string, string>
  metrics: { key: string; label: string; pct: boolean }[]; results: Record<string, string>; baseline: string
}
export interface DifficultyCell {
  battle: string; kind: string; kit: string; bot: string; primary: boolean
  lo: number; hi: number; runs: number; win: number; rounds: number; hp_left: number; verdict: 'ok' | 'easy' | 'hard'; timeouts: number
}
export interface DifficultyRun { running: boolean; variant: string; scope: string; actor: string; done: number; total: number; error: string; cells: DifficultyCell[] }
export interface DifficultyView {
  variant: string
  spec: { runs: number; primary: [string, string]; kinds: Record<string, string[]>; bands: Record<string, Record<string, Record<string, [number, number]>>> }
  columns: [string, string][]
  battles: { id: string; title: string; chapter: number; kind: string; primary: [string, string]; hash: string }[]
  report: { variant: string; finished: string; by: string; cells: DifficultyCell[]; hashes: Record<string, string> } | null
  run: DifficultyRun
}
export interface SupportCell { battle: string; support: string; usual: boolean; runs: number; win: number; rounds: number; calls: number }
export interface SupportRun { running: boolean; variant: string; scope: string; actor: string; done: number; total: number; error: string; cells: SupportCell[] }
export interface SupportView {
  variant: string
  runs: number
  heroes: { id: string; name: string; fee: number; opens: number; move: string; kind: string; power: number; range: number; cooldown: number }[]
  battles: { id: string; title: string; chapter: number; kind: string; primary: [string, string]; band: [number, number]; hash: string }[]
  report: { variant: string; finished: string; by: string; cells: SupportCell[]; hashes: Record<string, string> } | null
  run: SupportRun
}
export interface CompareRow { variant: string; verdicts: Verdict[]; bots: Record<string, { status: string; runs: number }> }

async function call<T>(method: string, path: string, body?: unknown): Promise<T> {
  const res = await fetch(path, {
    method,
    headers: { 'Content-Type': 'application/json', 'X-Actor': 'human' },
    body: body === undefined ? undefined : JSON.stringify(body),
  })
  const json = await res.json().catch(() => ({ error: `服务器返回了无法解析的内容（${res.status}）` }))
  if (!res.ok) throw new Error(json.error ?? json.detail ?? `请求失败（${res.status}）`)
  return json as T
}

const q = (params: Record<string, string | number | undefined | null>) => {
  const s = Object.entries(params)
    .filter(([, v]) => v !== undefined && v !== null && v !== '')
    .map(([k, v]) => `${k}=${encodeURIComponent(String(v))}`)
    .join('&')
  return s ? `?${s}` : ''
}
const vq = (variant: string) => (variant === 'baseline' ? undefined : variant)

export const api = {
  meta: () => call<Meta>('GET', '/api/meta'),
  variants: () => call<Variant[]>('GET', '/api/variants'),
  createVariant: (name: string, note: string, copy_from?: string) => call<Variant>('POST', '/api/variants', { name, note, copy_from }),
  deleteVariant: (name: string) => call('DELETE', `/api/variants/${encodeURIComponent(name)}`),
  adopt: (name: string) => call<{ files: string[] }>('POST', `/api/variants/${encodeURIComponent(name)}/adopt`),
  data: (variant: string) => call<StudioData>('GET', `/api/data${q({ variant: vq(variant) })}`),
  saveBattle: (variant: string, battle: Battle, summary = '') =>
    call<{ issues: Issue[] }>('PUT', `/api/variants/${encodeURIComponent(variant)}/battles/${battle.id}`, { battle, summary }),
  deleteBattle: (variant: string, id: string) => call('DELETE', `/api/variants/${encodeURIComponent(variant)}/battles/${id}`),
  saveTable: (variant: string, table: string, content: unknown, summary = '') =>
    call<{ issues: Issue[] }>('PUT', `/api/variants/${encodeURIComponent(variant)}/tables/${table}`, { content, summary }),
  startSim: (battle: string, variant: string, bots: string[], runs: number, seed = 0) =>
    call<Job>('POST', '/api/sims', { battle, variant: vq(variant) ?? null, bots, runs, seed }),
  jobs: () => call<Job[]>('GET', '/api/jobs'),
  cancelJob: (id: number) => call<Job>('POST', `/api/jobs/${id}/cancel`),
  results: (battle: string, variant: string) => call<Results>('GET', `/api/results${q({ battle, variant: vq(variant) })}`),
  compare: (battle: string) => call<CompareRow[]>('GET', `/api/compare${q({ battle })}`),
  saveTargets: (battle: string, spec: unknown) => call('PUT', `/api/targets/${battle}`, spec),
  replay: (battle: string, variant: string, bot: string, seed: number) =>
    call<Replay>('GET', `/api/replay${q({ battle, variant: vq(variant), bot, seed })}`),
  preview: (battle: string, variant: string) => call<{ url: string }>('POST', `/api/preview${q({ battle, variant: vq(variant) })}`),
  activity: () => call<Activity[]>('GET', '/api/activity'),
  supports: (variant: string) => call<SupportView>('GET', `/api/supports${q({ variant: vq(variant) })}`),
  runSupports: (variant: string, scope: string, runs = 0) =>
    call<SupportRun>('POST', '/api/supports/run', { variant: vq(variant) ?? null, scope, runs }),
  cancelSupports: () => call<SupportRun>('POST', '/api/supports/cancel', {}),
  difficulty: (variant: string) => call<DifficultyView>('GET', `/api/difficulty${q({ variant: vq(variant) })}`),
  runDifficulty: (variant: string, scope: string, runs = 0) =>
    call<DifficultyRun>('POST', '/api/difficulty/run', { variant: vq(variant) ?? null, scope, runs }),
  cancelDifficulty: () => call<DifficultyRun>('POST', '/api/difficulty/cancel', {}),
  setDifficultyBand: (kind: string, kit: string, bot: string, lo: number, hi: number) =>
    call('PUT', '/api/difficulty/bands', { kind, kit, bot, lo, hi }),
}

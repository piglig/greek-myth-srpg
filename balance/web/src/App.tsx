import { Button, Drawer, Menu, Modal, NumberInput, Stack, Text, TextInput, Textarea } from '@mantine/core'
import { notifications } from '@mantine/notifications'
import { IconArrowBigUpLines, IconChartHistogram, IconCheck, IconChevronDown, IconColumns3, IconMap2, IconPlayerPlay, IconPlus, IconTable, IconTrash } from '@tabler/icons-react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useEffect, useRef, useState } from 'react'
import { api, type Activity, type Battle, type Job } from './api'
import { CompareMode } from './CompareMode'
import { LevelMode } from './LevelMode'
import { ReplayMode } from './ReplayMode'
import { SimMode } from './SimMode'
import { isBaseline, useStore, type Mode } from './store'
import { TablesMode } from './TablesMode'

export const fail = (err: unknown) =>
  notifications.show({ color: 'red', title: '没有成功', message: err instanceof Error ? err.message : String(err), autoClose: 7000 })

const NAV: { value: Mode; label: string; icon: typeof IconMap2 }[] = [
  { value: 'level', label: '关卡', icon: IconMap2 },
  { value: 'tables', label: '数值', icon: IconTable },
  { value: 'sim', label: '模拟', icon: IconChartHistogram },
  { value: 'replay', label: '回放', icon: IconPlayerPlay },
  { value: 'compare', label: '对比', icon: IconColumns3 },
]

/** Server-sent events: keeps every open browser (and what the AI does through the API) in sync. */
function useLiveEvents() {
  const qc = useQueryClient()
  const [online, setOnline] = useState(false)
  useEffect(() => {
    if (new URLSearchParams(window.location.search).has('nolive')) return // static captures
    const es = new EventSource('/api/events')
    es.onopen = () => setOnline(true)
    es.onerror = () => setOnline(false)
    es.onmessage = (m) => {
      const { kind, data } = JSON.parse(m.data)
      if (kind === 'data') {
        qc.invalidateQueries({ queryKey: ['data'] })
        qc.invalidateQueries({ queryKey: ['variants'] })
        qc.invalidateQueries({ queryKey: ['results'] })
        qc.invalidateQueries({ queryKey: ['compare'] })
      } else if (kind === 'job') {
        const job = data as Job
        qc.setQueryData<Job[]>(['jobs'], (old = []) => [job, ...old.filter((j) => j.id !== job.id)])
        if (job.status !== 'running' && job.status !== 'queued') {
          qc.invalidateQueries({ queryKey: ['results'] })
          qc.invalidateQueries({ queryKey: ['compare'] })
          if (job.status === 'failed') notifications.show({ color: 'red', title: `模拟 ${job.battle} 失败`, message: job.error.slice(-300), autoClose: false })
        }
      } else if (kind === 'activity') {
        const entry = data as Activity
        qc.setQueryData<Activity[]>(['activity'], (old = []) => [entry, ...old].slice(0, 80))
        if (entry.actor === 'ai') notifications.show({ color: 'yellow', title: 'AI 刚刚', message: entry.text, autoClose: 5000 })
      }
    }
    return () => es.close()
  }, [qc])
  return online
}

function ActivityFeed({ items }: { items: Activity[] }) {
  return (
    <ol className="feed">
      {items.length === 0 && <li style={{ display: 'block' }} className="empty">还没有操作。你和 AI 做的每次修改、每次模拟都会记在这里。</li>}
      {items.map((a, i) => (
        <li key={`${a.ts}${i}`}>
          <span className={`who ${a.actor}`} title={a.actor === 'ai' ? 'AI 通过接口操作' : '在界面上操作'}>{a.actor === 'ai' ? 'AI' : '你'}</span>
          <div>
            {a.text}
            <time>{a.ts.slice(5, 16).replace('T', ' ')}{a.variant && a.variant !== 'baseline' ? ` · ${a.variant}` : ''}</time>
          </div>
        </li>
      ))}
    </ol>
  )
}

function stamp() {
  const d = new Date()
  const p = (n: number) => String(n).padStart(2, '0')
  return `${p(d.getMonth() + 1)}${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}`
}

export function NewVariantModal({ opened, onClose }: { opened: boolean; onClose: () => void }) {
  const { variant, set } = useStore()
  const qc = useQueryClient()
  const [name, setName] = useState('')
  const [note, setNote] = useState('')
  const [busy, setBusy] = useState(false)
  useEffect(() => { if (opened) { setName(`草稿-${stamp()}`); setNote('') } }, [opened])
  const create = async () => {
    setBusy(true)
    try {
      await api.createVariant(name.trim(), note.trim(), isBaseline(variant) ? undefined : variant)
      await qc.invalidateQueries({ queryKey: ['variants'] })
      set({ variant: name.trim() })
      onClose()
    } catch (e) { fail(e) } finally { setBusy(false) }
  }
  return (
    <Modal opened={opened} onClose={onClose} title="新建变体" centered>
      <Stack gap="sm">
        <Text size="sm" c="dimmed">变体是一份可以随意修改的副本。{isBaseline(variant) ? '它从当前基线开始。' : `它从「${variant}」复制。`}满意后再采用为基线，正式数据在那之前不会变。</Text>
        <TextInput label="名称" value={name} onChange={(e) => setName(e.currentTarget.value)} data-autofocus />
        <Textarea label="想验证什么（可不填）" placeholder="例如：让野猪守在台地上，看推崖比例" value={note} onChange={(e) => setNote(e.currentTarget.value)} autosize minRows={2} />
        <Button onClick={create} loading={busy} disabled={!name.trim()}>新建变体</Button>
      </Stack>
    </Modal>
  )
}

function NewBattleModal({ opened, onClose }: { opened: boolean; onClose: () => void }) {
  const { variant, set } = useStore()
  const qc = useQueryClient()
  const [id, setId] = useState('')
  const [title, setTitle] = useState('')
  const [w, setW] = useState<number>(12)
  const [d, setD] = useState<number>(12)
  const [busy, setBusy] = useState(false)
  const create = async () => {
    setBusy(true)
    try {
      const battle: Battle = {
        id: id.trim(), title: title.trim() || id.trim(), order: 99,
        heights: Array.from({ length: d }, () => '0'.repeat(w)),
        terrain: Array.from({ length: d }, () => '.'.repeat(w)),
        units: [
          { def: 'hero', id: 'hero', team: 'player', pos: [Math.floor(w / 2), d - 1], facing: 'N' },
          { def: 'wolf', id: 'wolf_1', team: 'enemy', pos: [Math.floor(w / 2), 0], facing: 'S' },
        ],
      }
      await api.saveBattle(variant, battle, `新建关卡 ${battle.id}「${battle.title}」`)
      await qc.invalidateQueries({ queryKey: ['data'] })
      set({ battleId: battle.id, mode: 'level' })
      onClose()
    } catch (e) { fail(e) } finally { setBusy(false) }
  }
  return (
    <Modal opened={opened} onClose={onClose} title="新建关卡" centered>
      <Stack gap="sm">
        <TextInput label="编号" description="用作文件名，例如 1-5" value={id} onChange={(e) => setId(e.currentTarget.value)} data-autofocus />
        <TextInput label="名称" placeholder="例如：1-5 双口洞穴" value={title} onChange={(e) => setTitle(e.currentTarget.value)} />
        <div style={{ display: 'flex', gap: 12 }}>
          <NumberInput label="宽（格）" min={4} max={24} value={w} onChange={(v) => setW(Number(v) || 12)} />
          <NumberInput label="深（格）" min={4} max={24} value={d} onChange={(v) => setD(Number(v) || 12)} />
        </div>
        <Button onClick={create} loading={busy} disabled={!/^[A-Za-z0-9_-]{1,24}$/.test(id.trim())}>新建关卡</Button>
      </Stack>
    </Modal>
  )
}

function AdoptModal({ opened, onClose }: { opened: boolean; onClose: () => void }) {
  const { variant, set } = useStore()
  const qc = useQueryClient()
  const { data } = useQuery({ queryKey: ['data', variant], queryFn: () => api.data(variant), enabled: opened })
  const [busy, setBusy] = useState(false)
  const adopt = async () => {
    setBusy(true)
    try {
      await api.adopt(variant)
      set({ variant: 'baseline' })
      await qc.invalidateQueries()
      notifications.show({ color: 'teal', title: '已采用', message: `「${variant}」现在是基线，正式数据已更新。` })
      onClose()
    } catch (e) { fail(e) } finally { setBusy(false) }
  }
  return (
    <Modal opened={opened} onClose={onClose} title={`采用「${variant}」为基线`} centered>
      <Stack gap="sm">
        <Text size="sm">这会把下面的改动写入正式数据（prototype/data/tables），并删除这个变体。与当前数据一致的模拟结果会一起转为基线结果。</Text>
        <ul className="difflist">
          {data?.diff.map((f) => [<li key={f.file} className="file">{f.file}</li>, ...f.lines.map((l, i) => <li key={f.file + i}>{l}</li>)])}
          {data && data.diff.length === 0 && <li className="file">这个变体和基线没有差别。</li>}
        </ul>
        <Button onClick={adopt} loading={busy} disabled={!data || data.diff.length === 0} leftSection={<IconArrowBigUpLines size={16} />}>采用为基线</Button>
      </Stack>
    </Modal>
  )
}

export function App() {
  const s = useStore()
  const qc = useQueryClient()
  const online = useLiveEvents()
  const [modal, setModal] = useState<'variant' | 'battle' | 'adopt' | null>(null)
  const [saving, setSaving] = useState(false)

  const variants = useQuery({ queryKey: ['variants'], queryFn: api.variants })
  const data = useQuery({ queryKey: ['data', s.variant], queryFn: () => api.data(s.variant) })
  const jobs = useQuery({ queryKey: ['jobs'], queryFn: api.jobs })
  const d = data.data
  const activeJob = jobs.data?.find((j) => j.status === 'running' || j.status === 'queued')

  // A variant deleted or adopted elsewhere: fall back to the baseline.
  useEffect(() => {
    if (!isBaseline(s.variant) && variants.data && !variants.data.some((v) => v.name === s.variant)) s.set({ variant: 'baseline' })
  }, [variants.data, s.variant]) // eslint-disable-line react-hooks/exhaustive-deps

  // Pick a battle, and keep the editable draft in step with the server unless there are unsaved edits.
  useEffect(() => {
    if (!d || d.variant !== s.variant) return
    const ids = Object.keys(d.battles)
    if (!ids.includes(s.battleId)) { s.set({ battleId: ids[0] ?? '' }); return }
    const key = `${s.variant}/${s.battleId}`
    const server = d.battles[s.battleId]
    if (key !== s.draftKey) s.loadDraft(key, server)
    else if (!s.dirty && JSON.stringify(server) !== JSON.stringify(s.draft)) s.loadDraft(key, server)
  }, [d, s.variant, s.battleId, s.dirty]) // eslint-disable-line react-hooks/exhaustive-deps

  // Autosave edits into the variant.
  const timer = useRef<number | undefined>(undefined)
  useEffect(() => {
    if (!s.dirty || !s.draft || isBaseline(s.variant)) return
    window.clearTimeout(timer.current)
    const draft = s.draft
    const variant = s.variant
    timer.current = window.setTimeout(async () => {
      setSaving(true)
      try {
        await api.saveBattle(variant, draft)
        // Refetch first: marking the draft clean while the cache still holds the old battle
        // would make the sync effect reload that old battle and drop the undo history.
        await qc.invalidateQueries({ queryKey: ['data', variant] })
        if (useStore.getState().draft === draft) useStore.getState().markSaved()
        qc.invalidateQueries({ queryKey: ['variants'] })
      } catch (e) { fail(e) } finally { setSaving(false) }
    }, 500)
    return () => window.clearTimeout(timer.current)
  }, [s.draft, s.dirty, s.variant, qc])

  const removeVariant = async () => {
    if (!window.confirm(`删除变体「${s.variant}」和它的模拟结果？`)) return
    try { await api.deleteVariant(s.variant); s.set({ variant: 'baseline' }); qc.invalidateQueries() } catch (e) { fail(e) }
  }

  const activity = useQuery({ queryKey: ['activity'], queryFn: api.activity })
  const [feedOpen, setFeedOpen] = useState(false)
  const latest = activity.data?.[0]
  const base = isBaseline(s.variant)
  const split = s.mode === 'level' || s.mode === 'sim' || s.mode === 'replay'
  const side = s.mode === 'sim' ? '520px' : s.mode === 'replay' ? '420px' : '320px'
  const errors = d?.issues.filter((i) => i.level === 'error' && (i.where === `battles/${s.battleId}` || !i.where.startsWith('battles/'))).length ?? 0
  const battle = d?.battles[s.battleId]
  return (
    <div className="shell">
      <header className="topbar">
        <div className="brand" title="战棋工坊 · Balance Studio">
          <svg width="30" height="30" viewBox="0 0 30 30" aria-label="战棋工坊">
            <polygon points="15,3 27,9.5 15,16 3,9.5" fill="#E8B95A" />
            <polygon points="3,9.5 15,16 15,27 3,20.5" fill="#B38733" />
            <polygon points="27,9.5 15,16 15,27 27,20.5" fill="#8F6B26" />
          </svg>
        </div>
        <div className="crumb">
          <Menu position="bottom-start" width={260} shadow="lg">
            <Menu.Target>
              <button className="crumb-btn" aria-label="切换关卡"><b>{battle?.title ?? '…'}</b><IconChevronDown size={15} /></button>
            </Menu.Target>
            <Menu.Dropdown>
              <Menu.Label>关卡</Menu.Label>
              {Object.values(d?.battles ?? {}).map((b) => (
                <Menu.Item key={b.id} rightSection={b.id === s.battleId ? <IconCheck size={15} /> : null} onClick={() => s.set({ battleId: b.id, replaySeed: null })}>{b.title}</Menu.Item>
              ))}
              <Menu.Divider />
              <Menu.Item leftSection={<IconPlus size={15} />} disabled={base} onClick={() => setModal('battle')}>{base ? '新建关卡（先新建变体）' : '新建关卡'}</Menu.Item>
            </Menu.Dropdown>
          </Menu>
          <span className="slash">/</span>
          <Menu position="bottom-start" width={280} shadow="lg">
            <Menu.Target>
              <button className="crumb-btn" aria-label="切换版本">
                {base ? <><span className="tag base">基线</span><small>正式数据 · 只读</small></> : <><span className="tag var">变体</span><b style={{ fontFamily: 'var(--sans)', fontSize: 14, fontWeight: 600 }}>{s.variant}</b></>}
                <IconChevronDown size={15} />
              </button>
            </Menu.Target>
            <Menu.Dropdown>
              <Menu.Label>版本</Menu.Label>
              <Menu.Item rightSection={base ? <IconCheck size={15} /> : null} onClick={() => s.set({ variant: 'baseline', replaySeed: null })}>基线（正式数据，只读）</Menu.Item>
              {(variants.data ?? []).map((v) => (
                <Menu.Item key={v.name} rightSection={v.name === s.variant ? <IconCheck size={15} /> : null} onClick={() => s.set({ variant: v.name, replaySeed: null })}>
                  {v.name}{v.note && <Text size="xs" c="dimmed" lineClamp={1}>{v.note}</Text>}
                </Menu.Item>
              ))}
              <Menu.Divider />
              <Menu.Item leftSection={<IconPlus size={15} />} onClick={() => setModal('variant')}>新建变体</Menu.Item>
              {!base && <Menu.Item color="red" leftSection={<IconTrash size={15} />} onClick={removeVariant}>删除「{s.variant}」</Menu.Item>}
            </Menu.Dropdown>
          </Menu>
        </div>
        <div className="spacer" />
        {base
          ? <Button size="xs" variant="light" leftSection={<IconPlus size={14} />} onClick={() => setModal('variant')}>新建变体</Button>
          : <Button size="xs" leftSection={<IconArrowBigUpLines size={14} />} onClick={() => setModal('adopt')}>采用为基线</Button>}
      </header>

      <nav className="nav" aria-label="工作区">
        {NAV.map((n) => (
          <button key={n.value} aria-current={s.mode === n.value ? 'page' : undefined} onClick={() => s.set({ mode: n.value })}>
            <n.icon size={21} stroke={1.6} />{n.label}
            {n.value === 'level' && errors > 0 && <span className="badge">{errors}</span>}
          </button>
        ))}
      </nav>

      <div className={`work${split ? ' split' : ''}`} style={{ ['--side' as string]: side }}>
        {!d || !s.draft ? (
          <div className="wide"><p className="empty">{data.isError ? `读取数据失败：${(data.error as Error).message}` : '正在读取数据…'}</p></div>
        ) : s.mode === 'level' ? <LevelMode data={d} onNewVariant={() => setModal('variant')} />
          : s.mode === 'tables' ? <TablesMode data={d} onNewVariant={() => setModal('variant')} />
          : s.mode === 'sim' ? <SimMode data={d} />
          : s.mode === 'replay' ? <ReplayMode data={d} />
          : <CompareMode data={d} />}
      </div>

      <footer className="statusbar">
        <span title={online ? '其他人和 AI 的修改会实时出现在这里' : '连接断开，正在重连'}><i className={`dot ${online ? 'on' : 'off'}`} />{online ? '实时同步' : '已断开'}</span>
        {!base && <span>{saving || s.dirty ? '保存中…' : '已保存'}</span>}
        <button className="ticker" onClick={() => setFeedOpen(true)} title="打开操作记录">
          {latest ? <><span className={`who ${latest.actor}`} style={{ width: 20, height: 20, borderRadius: 6, fontSize: 9.5 }}>{latest.actor === 'ai' ? 'AI' : '你'}</span><span>{latest.text}</span></> : <span>操作记录</span>}
        </button>
        {activeJob && <span>模拟 {activeJob.battle} · {activeJob.done}/{activeJob.total}<span className="jobbar"><i style={{ width: `${(100 * activeJob.done) / Math.max(1, activeJob.total)}%` }} /></span></span>}
      </footer>

      <Drawer opened={feedOpen} onClose={() => setFeedOpen(false)} position="right" size={400} title="操作记录" overlayProps={{ backgroundOpacity: 0.35 }}>
        <ActivityFeed items={activity.data ?? []} />
      </Drawer>
      <NewVariantModal opened={modal === 'variant'} onClose={() => setModal(null)} />
      <NewBattleModal opened={modal === 'battle'} onClose={() => setModal(null)} />
      <AdoptModal opened={modal === 'adopt'} onClose={() => setModal(null)} />
    </div>
  )
}

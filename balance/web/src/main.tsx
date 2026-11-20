import '@mantine/core/styles.css'
import '@mantine/notifications/styles.css'
import '@fontsource/noto-serif-sc/chinese-simplified-700.css'
import '@fontsource/noto-serif-sc/latin-700.css'
import '@fontsource/ibm-plex-sans/400.css'
import '@fontsource/ibm-plex-sans/500.css'
import '@fontsource/ibm-plex-sans/600.css'
import '@fontsource/ibm-plex-mono/400.css'
import '@fontsource/ibm-plex-mono/500.css'
import './styles.css'

import { createTheme, MantineProvider } from '@mantine/core'
import { Notifications } from '@mantine/notifications'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { createRoot } from 'react-dom/client'
import { App } from './App'

const theme = createTheme({
  primaryColor: 'gold',
  primaryShade: 5,
  autoContrast: true,
  luminanceThreshold: 0.45,
  colors: {
    gold: ['#fdf6e7', '#f8e8c2', '#f3d99b', '#eecb78', '#eac066', '#e8b95a', '#d2a245', '#b38733', '#8f6b26', '#6b4f1a'],
    dark: ['#e8ecf4', '#b4bccb', '#7f899c', '#5a6478', '#343c50', '#262d3d', '#1c2231', '#151a26', '#0e1320', '#0b0f18'],
  },
  fontFamily: "'IBM Plex Sans', 'Microsoft YaHei UI', 'PingFang SC', sans-serif",
  fontFamilyMonospace: "'IBM Plex Mono', Consolas, monospace",
  headings: { fontFamily: "'Noto Serif SC', 'Songti SC', serif" },
  defaultRadius: 8,
})

const client = new QueryClient({ defaultOptions: { queries: { staleTime: 5_000, refetchOnWindowFocus: false, retry: 1 } } })

createRoot(document.getElementById('root')!).render(
  <MantineProvider theme={theme} forceColorScheme="dark">
    <Notifications position="bottom-right" />
    <QueryClientProvider client={client}>
      <App />
    </QueryClientProvider>
  </MantineProvider>,
)

'use client'

import { ThemeProvider as MUIThemeProvider, createTheme } from '@mui/material/styles'
import CssBaseline from '@mui/material/CssBaseline'

const theme = createTheme({
  palette: {
    mode: 'light',
    primary: { main: '#1976d2' },
    secondary: { main: '#dc004e' },
    background: { default: '#f5f5f5' },
  },
  typography: {
    fontSize: 13,
    fontFamily: [
      '-apple-system', 'BlinkMacSystemFont', '"Segoe UI"',
      'Roboto', '"Helvetica Neue"', 'Arial', 'sans-serif',
    ].join(','),
  },
  spacing: 6,
  components: {
    MuiButton: { styleOverrides: { root: { textTransform: 'none' } } },
    MuiTableCell: { styleOverrides: { root: { padding: '6px 12px', fontSize: '0.8rem' } } },
    MuiInputBase: { styleOverrides: { root: { fontSize: '0.85rem' } } },
    MuiInputLabel: { styleOverrides: { root: { fontSize: '0.85rem' } } },
    MuiChip: { styleOverrides: { root: { fontSize: '0.75rem' } } },
  },
})

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  return (
    <MUIThemeProvider theme={theme}>
      <CssBaseline />
      {children}
    </MUIThemeProvider>
  )
}


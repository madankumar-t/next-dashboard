'use client'

import { useState, useEffect, Suspense, useCallback } from 'react'
import { useSearchParams } from 'next/navigation'
import { useDebounce } from '@/hooks/useDebounce'
import {
  Box,
  Grid,
  Card,
  CardContent,
  Typography,
  Select,
  MenuItem,
  FormControl,
  InputLabel,
  TextField,
  CircularProgress,
  OutlinedInput,
  Checkbox,
  ListItemText,
  Button,
  Alert,
  Snackbar,
  Chip,
} from '@mui/material'
import {
  Cloud,
  Storage,
  Dataset,
  Security,
  NetworkCheck,
  Apps,
  Refresh,
  Schedule,
  CloudQueue,
  Lock,
  Balance,
  Router,
  Language,
  Api,
  Public,
  Shield,
  ManageAccounts,
  GppGood,
} from '@mui/icons-material'
import { ServiceType } from '@/types'
import { api } from '@/lib/api'
import InventoryTable from '@/components/InventoryTable'
import SummaryCards from '@/components/SummaryCards'
import ResourceDetailDrawer from '@/components/ResourceDetailDrawer'

const SERVICES: Array<{ value: ServiceType; label: string; icon: React.ReactNode }> = [
  { value: 'ec2', label: 'EC2 Instances', icon: <Cloud /> },
  { value: 's3', label: 'S3 Buckets', icon: <Storage /> },
  { value: 'rds', label: 'RDS Instances', icon: <Dataset /> },
  { value: 'dynamodb', label: 'DynamoDB Tables', icon: <Dataset /> },
  { value: 'iam', label: 'IAM Roles', icon: <Security /> },
  { value: 'vpc', label: 'VPCs', icon: <NetworkCheck /> },
  { value: 'eks', label: 'EKS Clusters', icon: <Apps /> },
  { value: 'ecs', label: 'ECS Clusters', icon: <Apps /> },
  { value: 'lambda', label: 'Lambda Functions', icon: <Apps /> },
  { value: 'cloudfront', label: 'CloudFront Distributions', icon: <CloudQueue /> },
  { value: 'acm', label: 'ACM Certificates', icon: <Lock /> },
  { value: 'elb', label: 'Load Balancers', icon: <Balance /> },
  { value: 'nat', label: 'NAT Gateways', icon: <Router /> },
  { value: 'eip', label: 'Elastic IPs', icon: <Language /> },
  { value: 'apigw', label: 'API Gateway', icon: <Api /> },
  { value: 'route53', label: 'Route 53', icon: <Public /> },
  { value: 'sg', label: 'Security Groups', icon: <Shield /> },
  { value: 'cognito', label: 'Cognito', icon: <ManageAccounts /> },
  { value: 'waf', label: 'WAF Web ACLs', icon: <GppGood /> },
]

// DCLI's 5 active regions — used as fallback until the /regions API responds.
const DCLI_REGIONS = ['us-east-1', 'us-east-2', 'us-west-2', 'ap-south-1', 'sa-east-1']

function DashboardContent() {
  const searchParams = useSearchParams()

  const [service, setService] = useState<ServiceType>(
    (searchParams.get('service') as ServiceType) || 'ec2'
  )
  const [selectedAccounts, setSelectedAccounts] = useState<string[]>([])
  const [selectedRegions, setSelectedRegions] = useState<string[]>([])
  const [availableAccounts, setAvailableAccounts] = useState<Array<{ accountId: string; accountName: string }>>([])
  const [loadingAccounts, setLoadingAccounts] = useState(false)
  const [availableRegions, setAvailableRegions] = useState<string[]>(DCLI_REGIONS)
  const [search, setSearch] = useState('')
  const [selectedResource, setSelectedResource] = useState<any>(null)
  const [drawerOpen, setDrawerOpen] = useState(false)
  const [refreshing, setRefreshing] = useState(false)
  const [lastUpdate, setLastUpdate] = useState<string | null>(null)
  const [snackbar, setSnackbar] = useState<{ open: boolean; message: string; severity: 'success' | 'error' }>({
    open: false,
    message: '',
    severity: 'success',
  })

  const debouncedSearch = useDebounce(search, 500)

  const loadAccounts = useCallback(async () => {
    setLoadingAccounts(true)
    try {
      const accounts = await api.getAccounts()
      setAvailableAccounts(accounts)
    } catch {
      setAvailableAccounts([])
    } finally {
      setLoadingAccounts(false)
    }
  }, [])

  useEffect(() => {
    loadAccounts()
  }, [loadAccounts])

  const loadRegions = useCallback(async () => {
    try {
      const regions = await api.getRegions()
      if (regions.length > 0) {
        setSelectedRegions((currentSelectedRegions) =>
          currentSelectedRegions.filter((region) => regions.includes(region))
        )
        setAvailableRegions(regions)
      }
    } catch {
      // Keep the DCLI_REGIONS fallback already in state
    }
  }, [])

  useEffect(() => {
    loadRegions()
  }, [loadRegions])

  const loadMetadata = useCallback(async () => {
    try {
      const metadata = await api.getMetadata(service)
      setLastUpdate(metadata.lastUpdate || null)
    } catch {
      // Ignore errors
    }
  }, [service])

  useEffect(() => {
    loadMetadata()
  }, [service, loadMetadata])

  const handleRefresh = useCallback(async () => {
    setRefreshing(true)
    try {
      await api.refreshInventory(service, selectedAccounts.length > 0 ? selectedAccounts : undefined)
      setSnackbar({
        open: true,
        message: 'Refresh triggered successfully. Data will be updated shortly.',
        severity: 'success',
      })
      // Reload metadata after a delay
      setTimeout(() => {
        loadMetadata()
        api.clearCache()
      }, 2000)
    } catch (error) {
      setSnackbar({
        open: true,
        message: 'Failed to trigger refresh. Please try again.',
        severity: 'error',
      })
    } finally {
      setRefreshing(false)
    }
  }, [service, selectedAccounts, loadMetadata])

  return (
    <Box sx={{ display: 'flex', minHeight: '100vh', bgcolor: 'background.default' }}>
      {/* Main content shifts right by sidebar width on md+ screens */}
      <Box
        component="main"
        sx={{
          flexGrow: 1,
          minWidth: 0,
          width: 0,          // forces flex child not to overflow parent
          p: { xs: 1, sm: 1.5, md: 2 },
          overflowX: 'hidden',
        }}
      >
        <Grid container spacing={2} sx={{ width: '100%', m: 0 }}>
          {/* Filters */}
          <Grid item xs={12}>
            <Card>
              <CardContent>
                <Grid container spacing={2} alignItems="center">
                  <Grid item xs={12}>
                    <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2 }}>
                      <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                        {lastUpdate && (
                          <Chip
                            icon={<Schedule />}
                            label={`Last updated: ${new Date(lastUpdate).toLocaleString()}`}
                            size="small"
                            variant="outlined"
                          />
                        )}
                      </Box>
                      <Button
                        variant="contained"
                        color="primary"
                        startIcon={refreshing ? <CircularProgress size={16} /> : <Refresh />}
                        onClick={handleRefresh}
                        disabled={refreshing}
                      >
                        {refreshing ? 'Refreshing...' : 'Refresh Data'}
                      </Button>
                    </Box>
                  </Grid>
                  <Grid item xs={12} sm={6} md={3}>
                    <FormControl fullWidth>
                      <InputLabel>Service</InputLabel>
                      <Select
                        value={service}
                        label="Service"
                        onChange={(e) => setService(e.target.value as ServiceType)}
                      >
                        {SERVICES.map((s) => (
                          <MenuItem key={s.value} value={s.value}>
                            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                              {s.icon}
                              {s.label}
                            </Box>
                          </MenuItem>
                        ))}
                      </Select>
                    </FormControl>
                  </Grid>

                  <Grid item xs={12} sm={6} md={3}>
                    <FormControl fullWidth>
                      <InputLabel>Accounts</InputLabel>
                      <Select
                        multiple
                        value={selectedAccounts}
                        onChange={(e) =>
                          setSelectedAccounts(
                            typeof e.target.value === 'string'
                              ? e.target.value.split(',')
                              : (e.target.value as string[])
                          )
                        }
                        input={<OutlinedInput label="Accounts" />}
                        renderValue={(selected) => {
                          if (selected.length === 0) {
                            return <Typography color="text.secondary">All Accounts</Typography>
                          }
                          const names = selected
                            .map(id => availableAccounts.find(a => a.accountId === id)?.accountName || id)
                            .slice(0, 2)
                          const remaining = selected.length - names.length
                          return `${names.join(', ')}${remaining > 0 ? ` +${remaining} more` : ''}`
                        }}
                        disabled={loadingAccounts}
                      >
                        {loadingAccounts ? (
                          <MenuItem disabled>
                            <CircularProgress size={16} sx={{ mr: 1 }} />
                            Loading accounts...
                          </MenuItem>
                        ) : (
                          availableAccounts.map((a) => (
                            <MenuItem key={a.accountId} value={a.accountId}>
                              <Checkbox checked={selectedAccounts.includes(a.accountId)} />
                              <ListItemText primary={a.accountName || a.accountId} secondary={a.accountId} />
                            </MenuItem>
                          ))
                        )}
                      </Select>
                    </FormControl>
                  </Grid>

                  <Grid item xs={12} sm={6} md={3}>
                    <FormControl fullWidth>
                      <InputLabel>Regions</InputLabel>
                      <Select
                        multiple
                        value={selectedRegions}
                        onChange={(e) =>
                          setSelectedRegions(
                            typeof e.target.value === 'string'
                              ? e.target.value.split(',')
                              : (e.target.value as string[])
                          )
                        }
                        input={<OutlinedInput label="Regions" />}
                        renderValue={(selected) => {
                          if (selected.length === 0) {
                            return <Typography color="text.secondary">All Regions</Typography>
                          }
                          const shown = selected.slice(0, 2)
                          const remaining = selected.length - shown.length
                          return `${shown.join(', ')}${remaining > 0 ? ` +${remaining} more` : ''}`
                        }}
                      >
                        {availableRegions.map((r) => (
                          <MenuItem key={r} value={r}>
                            <Checkbox checked={selectedRegions.includes(r)} />
                            <ListItemText primary={r} />
                          </MenuItem>
                        ))}
                      </Select>
                    </FormControl>
                  </Grid>

                  <Grid item xs={12} sm={6} md={3}>
                    <TextField
                      fullWidth
                      label="Search"
                      value={search}
                      onChange={(e) => setSearch(e.target.value)}
                    />
                  </Grid>
                </Grid>
              </CardContent>
            </Card>
          </Grid>

          <Grid item xs={12}>
            <SummaryCards service={service} accounts={selectedAccounts} regions={selectedRegions} />
          </Grid>

          <Grid item xs={12}>
            <Card>
              <CardContent sx={{ p: 0, '&:last-child': { pb: 0 } }}>
                  <InventoryTable
                    service={service}
                    search={debouncedSearch}
                    accounts={selectedAccounts}
                    regions={selectedRegions}
                    onResourceClick={(r) => {
                      setSelectedResource(r)
                      setDrawerOpen(true)
                    }}
                  />
              </CardContent>
            </Card>
          </Grid>
        </Grid>
      </Box>

      <ResourceDetailDrawer
        open={drawerOpen}
        onClose={() => setDrawerOpen(false)}
        resource={selectedResource}
        service={service}
      />

      <Snackbar
        open={snackbar.open}
        autoHideDuration={6000}
        onClose={() => setSnackbar({ ...snackbar, open: false })}
        anchorOrigin={{ vertical: 'bottom', horizontal: 'right' }}
      >
        <Alert
          onClose={() => setSnackbar({ ...snackbar, open: false })}
          severity={snackbar.severity}
          sx={{ width: '100%' }}
        >
          {snackbar.message}
        </Alert>
      </Snackbar>
    </Box>
  )
}

export default function DashboardPage() {
  return (
    <Suspense
      fallback={
        <Box display="flex" justifyContent="center" alignItems="center" height="100vh">
          <CircularProgress />
        </Box>
      }
    >
      <DashboardContent />
    </Suspense>
  )
}

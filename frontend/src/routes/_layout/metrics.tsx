import { useSuspenseQuery } from "@tanstack/react-query"
import { createFileRoute } from "@tanstack/react-router"
import { Suspense } from "react"

import { MetricsService } from "@/client"
import RequirePermission from "@/components/Common/RequirePermission"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Skeleton } from "@/components/ui/skeleton"

export const Route = createFileRoute("/_layout/metrics")({
  component: Metrics,
  head: () => ({
    meta: [{ title: "Metrics - FastAPI Template" }],
  }),
})

function getMetricsQueryOptions() {
  return {
    queryFn: async () => (await MetricsService.readMetricsSummary()).data,
    queryKey: ["metrics"],
  }
}

function MetricsCards() {
  const { data } = useSuspenseQuery(getMetricsQueryOptions())

  const tiles = [
    { title: "Total users", value: data.total_users },
    { title: "Active users", value: data.active_users },
    { title: "Total items", value: data.total_items },
  ]

  return (
    <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
      {tiles.map((tile) => (
        <Card key={tile.title}>
          <CardHeader>
            <CardTitle className="text-sm font-medium text-muted-foreground">
              {tile.title}
            </CardTitle>
          </CardHeader>
          <CardContent>
            <span className="text-3xl font-bold tabular-nums">
              {tile.value}
            </span>
          </CardContent>
        </Card>
      ))}
    </div>
  )
}

function Metrics() {
  return (
    <RequirePermission permission="metrics:view">
      <div className="flex flex-col gap-6">
        <div>
          <h1 className="text-2xl font-bold tracking-tight">Metrics</h1>
          <p className="text-muted-foreground">
            A snapshot of activity across the workspace
          </p>
        </div>
        <Suspense
          fallback={
            <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
              <Skeleton className="h-32" />
              <Skeleton className="h-32" />
              <Skeleton className="h-32" />
            </div>
          }
        >
          <MetricsCards />
        </Suspense>
      </div>
    </RequirePermission>
  )
}

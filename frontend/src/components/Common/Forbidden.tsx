import { Link } from "@tanstack/react-router"
import { ShieldOff } from "lucide-react"

import { Button } from "@/components/ui/button"

interface ForbiddenProps {
  message?: string
}

/** Shown when a user reaches a route their role does not grant. */
const Forbidden = ({
  message = "You don't have permission to view this page. If you think this is a mistake, ask an administrator to review your role.",
}: ForbiddenProps) => (
  <div
    className="flex flex-col items-center justify-center gap-4 py-24 text-center"
    data-testid="forbidden"
  >
    <ShieldOff className="size-12 text-muted-foreground" />
    <h1 className="text-2xl font-bold tracking-tight">Access denied</h1>
    <p className="max-w-md text-muted-foreground">{message}</p>
    <Link to="/">
      <Button variant="outline">Go to dashboard</Button>
    </Link>
  </div>
)

export default Forbidden

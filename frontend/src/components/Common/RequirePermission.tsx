import type { PropsWithChildren } from "react"

import type { Permission } from "@/client"
import Forbidden from "@/components/Common/Forbidden"
import usePermissions from "@/hooks/usePermissions"

interface RequirePermissionProps {
  permission: Permission
}

/**
 * Renders children only for users holding `permission`, and an explicit
 * Access denied page otherwise — never a silent redirect, so a user who lands
 * on the URL directly understands what happened.
 */
const RequirePermission = ({
  permission,
  children,
}: PropsWithChildren<RequirePermissionProps>) => {
  const { can, isLoading } = usePermissions()

  if (isLoading) {
    return null
  }
  return can(permission) ? children : <Forbidden />
}

export default RequirePermission

import { useQuery } from "@tanstack/react-query"

import { type Permission, UsersService } from "@/client"
import { isLoggedIn } from "./useAuth"

/**
 * The frontend's view of what the current user may do.
 *
 * The list comes from the backend rather than from a hardcoded role table, so
 * a change to the permission matrix needs no frontend release. Hiding UI is a
 * convenience only — every one of these permissions is enforced again server
 * side.
 */
const usePermissions = () => {
  const { data: permissions, isLoading } = useQuery<Permission[], Error>({
    queryKey: ["permissions"],
    queryFn: async () => (await UsersService.readOwnPermissions()).data,
    enabled: isLoggedIn(),
  })

  const can = (permission: Permission) =>
    permissions?.includes(permission) ?? false

  return { permissions, can, isLoading }
}

export default usePermissions

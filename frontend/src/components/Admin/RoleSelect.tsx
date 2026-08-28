import type { Role } from "@/client"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"

/** What each role means, shown next to the option so the choice is informed. */
const ROLE_DESCRIPTIONS: Record<Role, string> = {
  admin: "Full access to users and settings",
  manager: "Can list users and view metrics",
  member: "Own profile and basic features only",
}

interface RoleSelectProps {
  value: Role
  onChange: (role: Role) => void
}

export const RoleSelect = ({ value, onChange }: RoleSelectProps) => (
  <Select value={value} onValueChange={onChange}>
    <SelectTrigger className="w-full">
      <SelectValue placeholder="Select a role" />
    </SelectTrigger>
    <SelectContent>
      {(Object.keys(ROLE_DESCRIPTIONS) as Role[]).map((role) => (
        <SelectItem key={role} value={role}>
          <span className="capitalize">{role}</span>
          <span className="text-muted-foreground ml-2 text-xs">
            {ROLE_DESCRIPTIONS[role]}
          </span>
        </SelectItem>
      ))}
    </SelectContent>
  </Select>
)

export default RoleSelect

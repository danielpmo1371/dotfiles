# Docker utilities for Nushell
# Enhanced docker commands with structured output

# Pretty docker ps with structured output and selected columns
export def dps [] {
  docker ps --format json
  | lines
  | each { |it| $it | from json }
  | select ID Names Image Status State Ports
  | update ID { |row| $row.ID | str substring 0..12 }
  | update Ports { |row| $row.Ports | str replace -a "0.0.0.0:" "" }
}

# Show all containers (including stopped)
export def dps-all [] {
  docker ps -a --format json
  | lines
  | each { |it| $it | from json }
  | select ID Names Image Status State Ports
  | update ID { |row| $row.ID | str substring 0..12 }
  | update Ports { |row| $row.Ports | str replace -a "0.0.0.0:" "" }
}

# Filter running containers only
export def dps-running [] {
  dps | where State == "running"
}

# Compact view - just essential info
export def dps-compact [] {
  docker ps --format json
  | lines
  | each { |it| $it | from json }
  | select Names Image Status
}

# Get container IPs
export def dps-ips [] {
  docker ps -q
  | lines
  | each { |id|
      {
        name: (docker inspect $id --format "{{.Name}}" | str trim -c '/')
        ip: (docker inspect $id --format "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}")
        id: ($id | str substring 0..12)
      }
    }
}

# Resource usage stats (non-streaming)
export def dstats [] {
  docker stats --no-stream --format json
  | lines
  | each { |it| $it | from json }
  | select Name CPUPerc MemUsage MemPerc NetIO BlockIO
}

# Get just container names
export def dps-names [] {
  docker ps --format "{{.Names}}" | lines
}

# Get just container IDs
export def dps-ids [] {
  docker ps --format "{{.ID}}" | lines
}

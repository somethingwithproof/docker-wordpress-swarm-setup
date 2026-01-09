# Security Policy

## Reporting a Vulnerability

We take security seriously. If you discover a security vulnerability, please report it responsibly.

| | |
|---|---|
| **Contact** | security@thomasvincent.dev |
| **Response time** | Within 48 hours |
| **Patch timeline** | Critical: 24-72 hours, High: 7 days, Medium: 30 days |

**Do not** open a public GitHub issue for security vulnerabilities.

### What to Include

When reporting a vulnerability, please provide:

1. Description of the vulnerability
2. Steps to reproduce
3. Potential impact
4. Suggested fix (if any)

## Supported Versions

| Version | Supported |
|---------|-----------|
| 1.x.x | Yes |
| < 1.0 | No |

---

## Security Architecture

This stack implements defense-in-depth with multiple security layers.

### Network Isolation

```
Internet
    │
    ▼
┌─────────────────────────────────────────┐
│  frontend network (overlay)             │
│  ┌─────────┐    ┌─────────────────────┐ │
│  │ Traefik │───▶│ Nginx (WordPress)   │ │
│  └─────────┘    └─────────────────────┘ │
└─────────────────────────────────────────┘
                        │
    ┌───────────────────┴───────────────────┐
    ▼                                       ▼
┌─────────────────────────────┐  ┌─────────────────────────┐
│ backend network (internal)  │  │ monitoring network      │
│ ┌─────────┐  ┌───────────┐  │  │ (internal)              │
│ │ MariaDB │  │   Redis   │  │  │ ┌──────────────┐        │
│ │ Galera  │  │ +Sentinel │  │  │ │  Prometheus  │        │
│ └─────────┘  └───────────┘  │  │ └──────────────┘        │
└─────────────────────────────┘  └─────────────────────────┘
        ▲                                   ▲
        │  No internet access               │  No internet access
        │  (internal: true)                 │  (internal: true)
```

**Key protections:**

- `backend` network: Marked `internal: true` — database and cache cannot initiate outbound connections
- `monitoring` network: Isolated metrics collection — reduces blast radius if monitoring is compromised
- Only Traefik exposes ports 80/443 to the internet

### Secrets Management

Secrets are handled using Docker Swarm's native secrets mechanism:

| Secret | Purpose | Rotation |
|--------|---------|----------|
| `mysql_root_password` | MariaDB root access | Manual |
| `mysql_password` | WordPress DB user | Manual |
| `redis_password` | Redis authentication | Manual |
| `traefik_dashboard_auth` | Dashboard access | Manual |

**Security properties:**
- Secrets stored encrypted in Swarm's Raft log
- Mounted as files at `/run/secrets/` (tmpfs, never written to disk)
- Only accessible to containers that explicitly declare them
- Not visible in `docker inspect` output

> **Warning:** The `./secrets/` directory contains plaintext files for initial setup. These are excluded from Git via `.gitignore`. Never commit secrets to version control.

### Database Security

The MariaDB configuration follows the principle of least privilege:

**WordPress user permissions:**
```sql
GRANT SELECT, INSERT, UPDATE, DELETE,
      CREATE, DROP, ALTER, INDEX,
      CREATE TEMPORARY TABLES, LOCK TABLES, REFERENCES
ON wordpress.*
TO 'wordpress'@'%';
```

**Explicitly denied:**
- `FILE` - No filesystem access
- `PROCESS` - Cannot view other processes
- `SUPER` - No administrative privileges
- `SHUTDOWN` - Cannot stop the server
- `GRANT OPTION` - Cannot modify permissions

See [`mariadb-init/01-create-database.sql`](mariadb-init/01-create-database.sql) for the complete configuration.

### Web Security Headers

Nginx includes OWASP-recommended security headers:

| Header | Value | Purpose |
|--------|-------|---------|
| `Content-Security-Policy` | `default-src 'self'; ...` | Prevents XSS and injection |
| `X-Frame-Options` | `SAMEORIGIN` | Prevents clickjacking |
| `X-Content-Type-Options` | `nosniff` | Prevents MIME sniffing |
| `Strict-Transport-Security` | `max-age=31536000; includeSubDomains; preload` | Enforces HTTPS |
| `Referrer-Policy` | `strict-origin-when-cross-origin` | Controls referrer information |
| `Permissions-Policy` | `camera=(), microphone=(), ...` | Disables unnecessary APIs |

See [`nginx.conf`](nginx.conf) for the complete configuration.

### TLS Configuration

- **Automatic certificates** via Let's Encrypt (ACME HTTP-01 challenge)
- **HTTP → HTTPS redirect** enforced at Traefik level
- **HSTS preload** enabled for maximum protection

### Access Control

| Endpoint | Authentication | Access |
|----------|----------------|--------|
| WordPress (`/`) | WordPress login | Public |
| Traefik Dashboard | HTTP Basic Auth | Restricted |
| Prometheus UI | HTTP Basic Auth | Restricted |
| Metrics endpoint (`:8082`) | None | Internal network only |

---

## Pre-Deployment Checklist

Complete these steps before deploying to production:

### Required

- [ ] Run `./scripts/setup-secrets.sh` to generate secure passwords
- [ ] Replace `your-domain.com` with your actual domain in `docker-stack.yml`
- [ ] Replace `YOUR_REAL_EMAIL@example.com` with a valid email for Let's Encrypt
- [ ] Verify DNS records point to your server

### Recommended

- [ ] Configure firewall to allow only ports 80 and 443
- [ ] Enable automatic security updates on the Docker host
- [ ] Set up log aggregation (e.g., Loki, ELK stack)
- [ ] Configure alerting in Prometheus
- [ ] Review Content-Security-Policy for your WordPress plugins/themes

### WordPress Hardening

After deployment, secure your WordPress installation:

- [ ] Install and configure a security plugin (e.g., Wordfence, Sucuri)
- [ ] Enable two-factor authentication for admin accounts
- [ ] Disable XML-RPC if not needed: add `xmlrpc.php` to Nginx deny list
- [ ] Keep WordPress core, themes, and plugins updated
- [ ] Use strong, unique passwords for all accounts
- [ ] Limit login attempts
- [ ] Disable file editing in wp-admin (`define('DISALLOW_FILE_EDIT', true);`)

---

## Vulnerability Disclosure Timeline

| Severity | Description | Response | Fix |
|----------|-------------|----------|-----|
| Critical | Remote code execution, data breach | 24 hours | 24-72 hours |
| High | Authentication bypass, privilege escalation | 48 hours | 7 days |
| Medium | Information disclosure, DoS | 7 days | 30 days |
| Low | Best practice violations | 14 days | 90 days |

## Security Updates

Subscribe to security notifications:
- [Docker Security Advisories](https://docs.docker.com/security/)
- [WordPress Security Releases](https://wordpress.org/news/category/security/)
- [MariaDB Security Announcements](https://mariadb.com/kb/en/security/)

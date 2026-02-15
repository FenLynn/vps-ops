# vps-ops Token Acquisition Guide

Follow these steps to generate the required tokens for your `vps-ops` setup.

## 1. CF_TOKEN (Cloudflare Tunnel)
This connects your VPS to Cloudflare Zero Trust without exposing ports.

1. Go to **[Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com/)**.
2. Navigate to **Networks > Tunnels**.
3. Click **Create a tunnel**.
4. Name it `vps-ops` (or similar) and save.
5. In the "Install connector" step, copy the **token** string from the Docker command. It looks like `eyJhIjoi...`.
   - *Example Command*: `docker run cloudflare/cloudflared:latest tunnel --no-autoupdate run --token eyJh...`
   - *You only need the token part.*

## 2. CF_DNS_API_TOKEN (Wildcard Certs)
This allows `acme.sh` to automatically renew SSL certificates via DNS challenge.

1. Go to **[Cloudflare Profile > API Tokens](https://dash.cloudflare.com/profile/api-tokens)**.
2. Click **Create Token**.
3. Use the **Edit zone DNS** template.
4. Under "Zone Resources", select **Include > Specific zone > yourdomain.com**.
5. Click **Continue to summary**, verify permissions, and **Create Token**.
6. Copy the token immediately (it won't be shown again).

## 3. PUSHPLUS_TOKEN (Notifications)
This sends system updates (like Watchtower alerts) to WeChat.

1. Go to **[PushPlus](http://www.pushplus.plus/)** and log in via WeChat.
2. Copy your **Token** from the homepage/dashboard.

## 4. TAILSCALE_AUTH_KEY (Optional Backdoor)
This provides emergency access if SSH fails.

1. Go to **[Tailscale Admin Console > Settings > Keys](https://login.tailscale.com/admin/settings/keys)**.
2. Click **Generate auth key**.
3. (Optional) Check "Reusable" if you plan to re-install often.
4. Add a tag like `tag:server` (recommended).
5. Click **Generate** and copy the key (starts with `tskey-...`).

---

**Next Steps**:
Paste these values into your `.env` file on the server.

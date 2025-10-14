# Buzzsaw — Affiliate-Side WooCommerce Plugin

Buzzsaw copies each product’s **Featured Image** and **original-art** (a custom field URL) into a **fixed NAS mount**, de-duplicates by file size, supports a **manual push screen with live progress**, and runs a **nightly randomized cron** (1–5 AM). It also supports **WordPress updates via GitHub releases**.

---

## Fixed Destination (DO NOT CHANGE)

```
/mnt/ccpi/mnt/nas/Website-Orders/<WordPress Site Title>/<WooCommerce Product Title>/
```

- Root is hardcoded to: `/mnt/ccpi/mnt/nas/Website-Orders`
- Mount should exist at `/mnt/ccpi` (e.g., via sshfs + systemd automount)

---

## What Buzzsaw Copies

For each **published WooCommerce product**:
1) **Featured image** (full-size attachment file)  
2) **original-art** — URL stored in custom field `original-art` (downloaded and saved)

**De-duplication:** If a target file already exists with the **same file size**, it is **not** recopied.

---

## Admin UI

Top-level menu:

```
Buzzsaw
 ├─ Settings
 └─ Push to thebeartraxs.com
```

- **Settings**: stores `buzzsaw_rest_key` (REST API key for thebeartraxs.com).
- **Push…**: a Start button to kick off copying. Shows live progress (percentage/pie). Continues in background if you navigate away.

---

## Cron (Automatic Nightly Push)

- Randomized once nightly between **1:00–4:59 AM** (server time)
- Hook: `buzzsaw_nightly_push`
- Scheduled on activation; cleared on deactivation

---

## Update Flow (WordPress ↔ GitHub)

- `buzzsaw.php` contains:
  - `Version: X.Y.Z`
  - `define('BUZZSAW_VERSION', 'X.Y.Z');`
  - `Update URI: https://github.com/emkowale/buzzsaw`
- The plugin checks **GitHub Releases** (`/releases/latest`), compares the **tag** (e.g. `v1.2.3`, trimmed to `1.2.3`) to `BUZZSAW_VERSION`.  
- If newer, WP shows an update. The **release asset ZIP** must contain a **single root folder named `buzzsaw/`**.

---

## Directory Structure

```
buzzsaw/
├─ buzzsaw.php                    # bootstrap, updater, constants
├─ includes/
│  ├─ class-buzzsaw-admin.php     # menu, pages, settings
│  ├─ class-buzzsaw-pusher.php    # scanning/copying products
│  └─ class-buzzsaw-cron.php      # nightly randomized cron
├─ assets/
│  ├─ css/admin.css               # admin styles
│  └─ js/push.js                  # progress UI (polling)
├─ README.md
├─ CHANGELOG.md
└─ release.sh                     # release automation
```

### `buzzsaw.php` (high level)
- Defines constants:
  - `BUZZSAW_VERSION` (matches release tag without `v`)
  - `BUZZSAW_BASE_PATH` = `/mnt/ccpi/mnt/nas/Website-Orders`
- Includes the 3 class files above
- Hooks WordPress updater (GitHub latest release)
- Registers activation/deactivation for cron

### `class-buzzsaw-admin.php`
- Adds one top-level **Buzzsaw** menu with two submenus
- Settings page saves `buzzsaw_rest_key`
- Push page starts the async batch and renders live progress

### `class-buzzsaw-pusher.php`
- For each Woo product:
  - Creates target folder:
    ```
    /mnt/ccpi/mnt/nas/Website-Orders/<Site Title>/<Product Title>/
    ```
  - Copies featured image if missing/different (size check)
  - Downloads `original-art` by URL if present (size check)
- Async batch via AJAX; persists progress (option/transient)

### `class-buzzsaw-cron.php`
- On activation: schedule at a random minute in 1–5 AM window
- On hook execution: run the same pusher routine

---

## Security / Safety

- Destination path is **hardcoded** (site owners cannot change it)
- Operates server-side; no secret exposure
- Graceful if mount is unavailable (skip + log minimal errors)

---

## Release & Update Process

- Bump version in `buzzsaw.php` header and `BUZZSAW_VERSION`
- Tag Git with `vX.Y.Z`
- Build archive so **zip root is `buzzsaw/`**
- Create GitHub Release and attach the zip

**With `release.sh`:**
```bash
./release.sh patch   # or: minor | major
```

---

## Rebuild From Scratch (Quick Steps)

1) Create directory `buzzsaw/` and subfolders exactly as above  
2) Add the four PHP files + assets (as described)  
3) In `buzzsaw.php`: add WP header, the constants, includes, updater hooks  
4) Ensure `BUZZSAW_BASE_PATH` = `/mnt/ccpi/mnt/nas/Website-Orders`  
5) Activate plugin in WP  
6) In **Buzzsaw → Settings**, set the REST key  
7) Test manual push in **Push to thebeartraxs.com**  
8) Confirm nightly cron schedules and runs  
9) Ship updates with `./release.sh patch` → GitHub Release → WP auto-update

---

## Troubleshooting

- **No WP update appears:** ensure a GitHub Release exists for `vX.Y.Z` with a zip whose root is `buzzsaw/`, and `BUZZSAW_VERSION` < `X.Y.Z`.
- **Copy fails:** ensure `/mnt/ccpi` is mounted and writable.
- **Duplicate menu:** only one `add_menu_page()` should create the root menu.

---

## License
MIT © Eric Kowalewski

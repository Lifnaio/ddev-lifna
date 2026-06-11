# DDEV Lifna

Connect an existing DDEV Drupal project to a Lifna-hosted environment.

This add-on installs a native DDEV provider named `lifna`, so existing projects can use:

```bash
ddev pull lifna
ddev push lifna
ddev lifna status
ddev lifna spinup
ddev lifna pause
```

Code remains Git-first. The provider only syncs the database and Drupal public files, matching DDEV hosting-provider conventions.

## Install

From a DDEV project root:

```bash
ddev add-on get Lifnaio/ddev-lifna
ddev restart
```

For local development of this add-on:

```bash
ddev add-on get /path/to/ddev-lifna
ddev restart
```

## Connect A Project

In Lifna, open the site export page and create a DDEV local access token for the target environment.

Then run:

```bash
ddev lifna connect \
  --site=my-site \
  --environment=main \
  --base-url=https://app.lifna.com
```

Paste the token when prompted.

The command writes:

- `.lifna/environment.json` with the Lifna site/environment link.
- `.ddev/lifna/.env` with the local token.

Both are ignored locally by generated `.gitignore` files.

## Daily Workflow

```bash
ddev lifna status
ddev pull lifna
ddev push lifna
ddev lifna pause
ddev lifna spinup
ddev lifna open
```

`ddev pull lifna` downloads the Lifna database and public files into the DDEV project.

`ddev push lifna` uploads the local database and public files back to the scoped Lifna environment. Treat pushes to production with care.

## Required Lifna API

The add-on calls:

```text
GET  /api/ddev/v1/sites/{site}/environments/{environment}
GET  /api/ddev/v1/sites/{site}/environments/{environment}/pull/database
GET  /api/ddev/v1/sites/{site}/environments/{environment}/pull/files
POST /api/ddev/v1/sites/{site}/environments/{environment}/push/database
POST /api/ddev/v1/sites/{site}/environments/{environment}/push/files
POST /api/ddev/v1/sites/{site}/environments/{environment}/spinup
POST /api/ddev/v1/sites/{site}/environments/{environment}/pause
```

Authentication uses a bearer token created in Lifna and scoped to one site/environment.

## Publish

The recommended GitHub repo name is `ddev-lifna`, with the `ddev-get` topic added for DDEV add-on discovery.

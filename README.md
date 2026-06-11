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

For local Lifna platform development only, set `LIFNA_DEV_MODE=1` or pass `--dev` when connecting to a local HTTPS or localhost URL.

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

`ddev push lifna` uploads the local database and public files back to the scoped Lifna environment. Pushes to protected environments such as `main`, `live`, `prod`, or `production` require a typed confirmation.

## Security Model

The add-on uses a Lifna local access token created in the Lifna UI. Tokens are scoped to one site, one environment, limited actions, and an expiry date.

Tokens are read from the secure prompt during `ddev lifna connect` or from `LIFNA_TOKEN`. Do not pass tokens as command-line arguments and do not commit `.ddev/lifna/.env`.

Production connections must use `https://app.lifna.com` unless explicit dev mode is enabled.

## Testing

The test suite is written with Bats and includes shell-level security tests plus a DDEV install smoke test.

```bash
bash -n commands/host/lifna lifna/client.sh
shellcheck commands/host/lifna lifna/client.sh
yamllint .
bats tests
```

GitHub Actions runs the same lint checks and uses DDEV's add-on test action to install the add-on into a disposable DDEV project.

## Publish

The recommended GitHub repo name is `ddev-lifna`, with the `ddev-get` topic added for DDEV add-on discovery.

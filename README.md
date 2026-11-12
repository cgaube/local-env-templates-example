# local-env-templates-example

A starter source for [local-env](https://github.com/cgaube/local-env): a small
example of each thing that a source can have. Try it as it is, or copy it to
make the source of your team.

- Docker templates: a stack that builds its own image, and one that asks for a
  value when you deploy it
- Ansible roles and a profile that only print messages: they change nothing on
  your Mac
- The tools to check the templates before each commit, and to build images on
  GitHub
- An onboarding script that sets up a new employee's Mac with one command

## Try it

```sh
local-env sources add https://github.com/cgaube/local-env-templates-example
```

Then deploy a template from the dashboard's Docker page
(`https://local-env.dev.test/docker`) or with `local-env deploy acme/hello`, and
install the tools with `local-env install example_profile`.

## Make your own source

1. On GitHub, click **Use this template**, then **Create a new repository**.
   Your repo gets the files, but not the history. It can be private.
2. In `local-env.yml`, set `name:` (a short id, unique among your sources) and
   `label:` (the name the dashboard shows).
3. Replace the examples with your templates, roles and profiles, and remove what
   you do not need: a source can have only `docker/`, or only `ansible/`.
   - For each collection you keep or add, set `namespace:` in its `galaxy.yml`
     to your team or company. local-env fails if two sources have a collection
     of the same name, so do not keep `acme`.
   - Set `repository:` in `ansible/*/galaxy.yml` and `repository.url` in
     `docker/templates.json` to the URL of your repo.
   - Set `LOCAL_ENV_SOURCE_URL` in `onboarding.sh` to the URL of your repo (see
     [Onboard your team](#onboard-your-team)).
4. Add your repo to local-env: `local-env sources add <your repo URL>`.

The guide for each part:
[Write a source](https://cgaube.github.io/local-env/write-a-source/source-repo).

## Layout

```
local-env.yml                      # the manifest: name, label and logins
docker/templates.json              # the template list (Portainer format)
docker/<name>/compose.yaml         # one stack
ansible/<collection>/              # an Ansible collection: acme.<collection>
ansible/<collection>/galaxy.yml    # its namespace, name and dependencies
ansible/<collection>/roles/<role>/ # a role: a tool in the dashboard catalog
onboarding.sh                      # sets up a new employee's Mac
scripts/check-templates.sh         # checks docker/, run before each commit
.github/actions/image/             # builds an image and pushes it to ghcr.io
.github/workflows/image-<name>.yml # one workflow for each image
tests/ansible/                     # tries the roles with --check
```

## Docker templates

| Template   | What it shows                                                       |
| ---------- | ------------------------------------------------------------------- |
| `hello`    | A stack that builds its image from `docker/hello/site/`             |
| `greeting` | A stack that asks for a value when you deploy it (`${GREETING:?…}`) |

Each template is a stack (`"type": 3` in `templates.json`) with its own
`docker/<name>/compose.yaml`, which sets a unique top-level `name:` and a
`VIRTUAL_HOST`: `hello` is served at `https://hello.dev.test`.

How to write them:
[Docker templates](https://cgaube.github.io/local-env/write-a-source/docker-templates).

To add a template: create `docker/<name>/compose.yaml`, add its entry to
`docker/templates.json`, commit and push, then run `local-env sources sync`. It
shows on the dashboard's Docker page; **Deploy** asks for its values, reads its
secrets from your vault, and deploys it in Dockhand. A change to a template
reaches the stacks deployed from it with the next `local-env sources sync`.

### Prebuilt images

A stack can build its image when you deploy it, like `hello`: that is the
default, and needs nothing more. When you need a prebuilt image (a private one,
or one that takes long to build), GitHub can build it and push it to
`ghcr.io/<owner>/<repo>/<name>`. `.github/workflows/image-hello.yml` is an
example, which builds `docker/hello/site/`; the steps are in the shared action
`.github/actions/image/action.yml`.

- The example runs only by hand (Actions tab → **Image hello** → **Run
  workflow**): a repo made from this template builds no image it does not use.
- To add an image, copy `image-hello.yml` to `image-<name>.yml`, change the
  name, the `paths` and the inputs of the action, then uncomment its `push` and
  `pull_request` triggers: it builds the image again when one of its `paths`
  changes on `main`, and a pull request builds it without pushing it. Then use
  the image in the compose file: `image: ghcr.io/<owner>/<repo>/<name>`.
- After a push, the workflow deletes the old versions. It keeps 2 old versions
  in addition to `latest` (action input `keep`).
- The default platform is `linux/arm64` (Macs with Apple silicon). For x86
  machines too, set the action input `platforms` to `linux/arm64,linux/amd64`.

An image gets the visibility of the repo. If your repo is private, add a
`registry` login to `local-env.yml`: see
[Private images](https://cgaube.github.io/local-env/write-a-source/docker-templates).

## Ansible roles and profiles

| Collection      | Roles                                                       |
| --------------- | ----------------------------------------------------------- |
| `acme.examples` | `hello_world`, `hello_root`, `hello_galaxy`, `hello_inputs` |
| `acme.profiles` | `example_profile`                                           |

| Role           | What it shows                                                 |
| -------------- | ------------------------------------------------------------- |
| `hello_world`  | The simplest role: it says hello                              |
| `hello_root`   | `become`: it runs `whoami` with sudo                          |
| `hello_galaxy` | A dependency on a collection from Galaxy (`padminisys.hello`) |
| `hello_inputs` | Inputs: a text, a choice, a bool, an int, a list and a secret |

How to write them:
[Tools and profiles](https://cgaube.github.io/local-env/write-a-source/tools)
and
[Tool variables](https://cgaube.github.io/local-env/write-a-source/variables).

### The example profile

`acme.profiles.example_profile` contains `hello_inputs`, sets one of its values
(`hello_inputs_greeting: Bonjour`) and asks for one of its own
(`example_profile_team`). Its `local-env.yml` sets the name local-env shows
(`label`) and the stacks it needs (`stacks`, none here).

### Use the collections without local-env

With Ansible 2.16 or later, install all the collections of `ansible/`, then run
a playbook that lists the roles by their full name:

```sh
ansible-galaxy collection install -p ./collections \
  'git+https://github.com/cgaube/local-env-templates-example.git#/ansible/,main'
ansible-playbook playbook.yml   # add -K for hello_root
```

## Secrets

Roles and stacks can get a secret (a token, a password) from your company's
vault: AWS Secrets Manager or HashiCorp Vault. Say where it is in
`local-env.yml` (`logins:` and `secrets:`, commented out there). local-env reads
it with the login: it never asks for it and never writes it to the disk.

- **A role** declares it as an input with `no_log: true`
  (`meta/argument_specs.yml`). local-env gives it to Ansible.
- **A stack** uses it in its compose file, in the list form, so that Dockhand
  hides it in its pages: `- API_TOKEN=${API_TOKEN:?from the vault}`. local-env
  saves it in Dockhand as a secret variable of the stack.

How: [Tool secrets](https://cgaube.github.io/local-env/write-a-source/secrets)
and the Secrets section of
[Docker templates](https://cgaube.github.io/local-env/write-a-source/docker-templates).

## Onboard your team

`onboarding.sh` sets up a new employee's Mac with one command: it installs
Homebrew if it is missing, then local-env, sets it up and starts it, adds this
source and asks for the employee's profile. Run it again at any time: each step
skips what is already done.

1. Set the values at the top: `LOCAL_ENV_SOURCE_URL` (your repo),
   `LOCAL_ENV_DOMAIN` and `LOCAL_ENV_PROFILE` (empty: the employee picks one).
   An environment variable of the same name wins. Without a running Docker, the
   script installs and starts Colima.
2. Serve it where a new Mac can download it without a login. A public repo can
   use its raw URL; for a private repo, copy the file to your intranet or to a
   public page.
3. Give your team the command:

   ```sh
   /bin/bash -c "$(curl -fsSL https://example.com/local-env/onboarding.sh)"
   ```

To try it with this repo:

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/cgaube/local-env-templates-example/main/onboarding.sh)"
```

The guide:
[Onboard your team](https://cgaube.github.io/local-env/write-a-source/onboard-your-team).

## Contributing

Run `mise install` once: it installs the tools from `mise.toml` and the git
hooks. Before each commit, the hooks format the staged files (oxfmt) and check
the templates (`scripts/check-templates.sh`): every stackfile exists, every
compose file is valid and has a unique top-level `name:`. They also check the
shell scripts with shellcheck.

To try a change to the Ansible collections before you push it, run
`mise run ansible:check` (you need Ansible 2.16 or later). It installs the
collections of `ansible/` in `tests/ansible/collections/`, then runs
`tests/ansible/playbook.yml` with `--check`: Ansible shows what it would change,
and changes nothing. To test a role, add it to that playbook. If a role uses
`become`, run `mise run ansible:check -- -K`: Ansible asks for the sudo
password.

## License

[MIT-0](LICENSE): copy and change it freely, no attribution needed.

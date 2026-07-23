# DevExpress Suite License Setup

This note records the repeatable workstation setup for licensed DevExpress
.NET components installed from NuGet. Do not commit the downloaded license
file, its contents, account credentials, or DevExpress NuGet feed keys to this
repository.

## Why this is needed

Starting with DevExpress v25.1, NuGet-based builds need a valid DevExpress
.NET license key at compilation time. The DevExpress source generator embeds
license information into the compiled assembly. A project compiled without a
valid key can still run, but Reporting and other components display evaluation
banners or watermarks.

The Windows DevExpress Unified Installer registers the key automatically.
macOS and Linux do not need that installer: download the license file and put
it in the operating system's expected user-level location.

## Obtain the license file

1. Sign in to the
   [DevExpress Download Manager](https://www.devexpress.com/ClientCenter/DownloadManager).
2. Locate the assigned DevExpress subscription and download the **.NET License
   Key**.
3. Keep the downloaded filename exactly as `DevExpress_License.txt`.

The account must have an appropriate developer license assigned to it. The key
must cover the DevExpress major version used by the project. For example,
v25.2 packages require a v25.2 or newer key. A newer key can license older
DevExpress versions.

## macOS setup

Install the downloaded file at the exact, case-sensitive path:

```text
~/Library/Application Support/DevExpress/DevExpress_License.txt
```

From Terminal:

```sh
mkdir -p "$HOME/Library/Application Support/DevExpress"
cp "$HOME/Downloads/DevExpress_License.txt" \
  "$HOME/Library/Application Support/DevExpress/DevExpress_License.txt"
chmod 600 "$HOME/Library/Application Support/DevExpress/DevExpress_License.txt"
```

Do not print the file contents while verifying it. Check only that the file
exists and has owner-only permissions:

```sh
test -s "$HOME/Library/Application Support/DevExpress/DevExpress_License.txt"
stat -f '%Sp %Su %N' \
  "$HOME/Library/Application Support/DevExpress/DevExpress_License.txt"
```

## Linux setup

Use the exact, case-sensitive path:

```text
~/.config/DevExpress/DevExpress_License.txt
```

Apply directory mode `700` and file mode `600`.

## Windows setup

The DevExpress Unified Installer normally registers the license after login.
For a NuGet-only setup, download the same file and place it at:

```text
%AppData%\DevExpress\DevExpress_License.txt
```

## Rebuild after registration

Registration affects compilation, not an assembly that was already built.
Stop the application and perform a clean rebuild after installing or updating
the key. If the evaluation banner remains, delete the affected projects'
`bin` and `obj` outputs before rebuilding.

Successful verification means:

- DevExpress build warnings such as `DX1000`, `DX1001`, or `DX1002` are gone.
- Reporting pages no longer show the orange evaluation banner.
- Generated reports no longer contain the evaluation watermark.

## Alternative registration methods

DevExpress also supports these exact, case-sensitive environment variables:

- `DevExpress_LicensePath`: path to a custom directory containing the license
  file.
- `DevExpress_License`: the license file contents.

Prefer the user-level license file for workstation development. It avoids
placing a secret in shell history and avoids IDE environment-inheritance
problems. If an environment variable is used, it must be available to the
build process, not only to the running application.

## CI and container builds

The personal .NET license key is needed only while compiling. Provide it to
the build stage through the CI secret store or a Docker BuildKit secret. Do
not copy it into the repository, application resources, deployment artifact,
or final container image.

An already licensed assembly can run without the personal key on the target
machine.

## Important distinctions

- The DevExpress .NET license key is not the DevExpress NuGet feed key. The
  feed key downloads packages; the .NET key licenses compilation. Keep both
  secret.
- Browser-side DevExtreme licensing is separate. A DevExtreme `W0019` warning
  requires the DevExtreme runtime-key workflow; the .NET license file alone
  does not register that client-side key.
- Telerik/Kendo uses a different license file and workflow documented in
  [kendo-suite-license.md](kendo-suite-license.md).

## Official references

- [License Key for DevExpress .NET Products](https://docs.devexpress.com/GeneralInformation/405494/trial-register/set-up-your-dev-express-license-key)
- [How to Install DevExpress Products](https://docs.devexpress.com/GeneralInformation/116042/installation/install-products)

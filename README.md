###############################################
###  CISR TECHNICAL  -  22 OCTOBER 2026     ###
###  Remove-Emudhra Certificates Sanitation ###
###                                         ###
###############################################

# remove-emudhra

Linux and Windows host scripts to remove the eMudhra certificates that may exist on their system. 

Created in response to the revelation that the eMudhra certificate's 'secret key' had been found to be a single digit...  '4' .   CISR Technical takes no responsibility for the usage, operation or consequences of running the scripts provided, these were developed for the purpose of sanitizing CISR systems only - should you choose to run them; it's all on you buddy.

#===========================================================================#

DISCLAIMER - You are responsible for the consequences of using these scripts, not us - all script contents are plain and auditable, check variables and run in a sandbox for potential ill effects and perform appropriate before use in any production system or services.

CISR Technical accepts no liability or responsibility for the use of the scripts, applications or software provided via GitHub. By downloading,
installing or using any application, software or script, the user accepts full responsibility, liability and ownership of the actions they perform with it and of any and all potential or realised consequences arising from its use.

It is strongly in the user's interest to run any application, software or script in a safe sandboxed environment prior to use on production systems. All software is provided "as is", without warranty of any kind, express or implied.

#===========================================================================#


October 2026 eMudhra certificates exposure: Eight emSign intermediate CA certificates were compromised and the emSign ECC Root CA - G3 root was removed from the Mozilla and Chrome root programmes. This toolkit identifies and removes all eMudhra / emSign certificates (roots, intermediates and cross-signed copies) from every trust store on a machine and prevents them from being silently re-added.

Script functionality:

distrust-emudhra.sh (Ubuntu 22.xx+ / Debian 13.x+ Linux, run as root):

    Scans certificate contents (subject and issuer) rather than filenames, so it catches roots, intermediates and cross-signed variants regardless of how they are labelled
    Removes matching certificates from the system trust store (/etc/ssl/certs), NSS databases (Firefox, Thunderbird, Chromium/Chrome), every Java cacerts keystore on disk and the Python certifi bundle
    Writes blacklist entries into /etc/ca-certificates.conf so future ca-certificates package upgrades cannot reintroduce the certificates
    Rebuilds the trust store and verifies the result before exiting

distrust-emudhra.bat (Windows, run elevated):

    Searches the machine and user root, AuthRoot and intermediate stores for matching certificates
    Exports a backup of each, adds it to the Disallowed (Untrusted Certificates) store — an explicit "never trust" entry that survives Certificate Trust List updates — then deletes it from the trusted stores

Properties:

    Fully offline — no network access required; no third-party services, accounts or telemetry
    Safe to re-run — idempotent, with a timestamped backup of everything before any change is made
    Logged — every action is recorded for audit

Limitations
A script can only distrust a CA on the machine it runs on; true global invalidation is performed by the browser/OS root programmes (already completed for this incident). Container images, Go binaries built with unpatched toolchains and pinned-certificate configurations must be rebuilt separately.


USAGE: 

#Linux hosts (Ubuntu, Debian & derivatives):
  sudo chmod +x <path-to-file>/remove-emudhra.sh
  ./remove-elmudhra.sh

#Windows hosts (Win 11/10):
  <path-to-file> .\remove-emudhra.bat

#===========================================================================#

DISCLAIMER REMINDER - You are responsible for the consequences of using these scripts, not us - all script contents are plain and auditable, check variables and run in a sandbox for potential ill effects before using on any production system.

CISR Technical accepts no liability or responsibility for the use of the scripts, applications or software provided via GitHub. By downloading,
installing or using any application, software or script, the user accepts full responsibility, liability and ownership of the actions they perform with it and of any and all potential or realised consequences arising from its use.

It is strongly in the user's interest to run any application, software or script in a safe sandboxed environment prior to use on production systems. All software is provided "as is", without warranty of any kind, express or implied.

#===========================================================================#

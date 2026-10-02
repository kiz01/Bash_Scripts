# OCI Ampere A1 Auto-Provisioner

A Bash script that continuously attempts to provision an Oracle Cloud Infrastructure (OCI) Ampere A1 instance through OCI Resource Manager.

The script is designed for situations where an Ampere A1 shape is temporarily unavailable due to OCI capacity constraints. It repeatedly submits an Apply job, monitors the job, waits between attempts, and retries until the requested provisioning succeeds.

After successful provisioning, the script sends a Telegram notification and exits.

---

## Features

- OCI Resource Manager integration
- Automatic Apply job submission
- Automatic retry when provisioning fails
- Resource Manager job status monitoring
- API/rate-limit error cooldown handling
- Telegram notification on successful provisioning
- Designed for unattended 24/7 execution
- Simple Bash implementation
- Can be updated through Git

---

## How It Works

The script follows this workflow:

```text
Start
  |
  v
Submit OCI Resource Manager Apply Job
  |
  v
Job submitted successfully?
  |
  +---- No ----> Wait 5 minutes
  |                 |
  |                 +----> Retry
  |
  Yes
  |
  v
Monitor Job Every 30 Seconds
  |
  +---- SUCCEEDED ----> Send Telegram Notification
  |                          |
  |                          v
  |                        Exit
  |
  +---- FAILED/CANCELED --> Wait 3 Minutes
                              |
                              v
                            Retry
```

The script is intended to run continuously until OCI successfully provisions the requested instance.

---

## Prerequisites

Before running the script, make sure the following are available:

**Required**
- Linux system
- Bash
- Oracle Cloud Infrastructure (OCI) CLI
- Authenticated OCI CLI configuration
- An existing OCI Resource Manager Stack
- `curl`
- Network connectivity

**Optional**
- Telegram Bot
- Telegram Chat ID

Telegram is used to send a notification after successful provisioning.

### Verify Prerequisites

Check Bash:
```bash
bash --version
```

Check OCI CLI:
```bash
oci --version
```

Check curl:
```bash
curl --version
```

Verify OCI CLI Authentication:
```bash
oci iam region-subscription list
```
The command should return information about the OCI regions available to your account. If OCI CLI authentication is not configured, configure it before continuing.

---

## Installation

### 1. Clone the Repository

Clone the repository using SSH:
```bash
git clone git@github.com:kiz01/REPOSITORY_NAME.git
```
Enter the repository:
```bash
cd REPOSITORY_NAME
```
*(Replace `REPOSITORY_NAME` with the actual GitHub repository name.)*

### 2. Configure the Script

Open the script:
```bash
nano oci_loop.sh
```
At the beginning of the script, configure these variables:
```bash
STACK_ID="PASTE_YOUR_STACK_OCID_HERE"
BOT_TOKEN="PASTE_YOUR_BOT_TOKEN_HERE"
CHAT_ID="PASTE_YOUR_CHAT_ID_HERE"
```
Replace them with your actual values.

- **STACK_ID**: The OCID of the OCI Resource Manager Stack that contains the Terraform configuration for the instance you want to provision. 
  *(Example: `STACK_ID="ocid1.ormstack.oc1..."`)*
- **BOT_TOKEN**: The API token generated for your Telegram bot.
  *(Example: `BOT_TOKEN="123456789:ABCdefGHI..."`)*
- **CHAT_ID**: The Telegram Chat ID where the notification should be sent.
  *(Example: `CHAT_ID="987654321"`)*

**Security Warning:** The values shown in this repository are placeholders only. While your `STACK_ID` and `CHAT_ID` are standard identifiers and not strictly secret, your Telegram `BOT_TOKEN` is a highly sensitive credential. Never commit your actual Telegram Bot Token, OCI private keys, or other sensitive credentials to a public GitHub repository.

### 3. Verify the OCI Resource Manager Stack

Before starting the automation loop, verify that the configured Stack is accessible:
```bash
oci resource-manager stack get --stack-id "$STACK_ID"
```
The command should return information about the Resource Manager Stack. If the command fails, verify OCI CLI authentication, Stack OCID, OCI IAM permissions, OCI region, and Compartment access. Do not start the automated loop until the Stack can be accessed successfully.

### 4. Make the Script Executable

Run:
```bash
chmod +x oci_loop.sh
```
Verify:
```bash
ls -l oci_loop.sh
```
The file should have executable permissions similar to `-rwxr-xr-x`.

---

## Test Run

Before running the script continuously in the background, run it directly:
```bash
./oci_loop.sh
```
You should see output similar to:
```text
[DATE] Starting Resource Manager Stack loop...
[DATE] Triggering Apply job...
[DATE] Submitted Job: ocid1.ormjob.oc1...
[DATE] Current Job Status: ACCEPTED
[DATE] Current Job Status: IN_PROGRESS
```
The script will continue monitoring the Resource Manager job.

### Successful Provisioning
When the Resource Manager job succeeds, the script will display:
```text
[DATE] Instance Provisioned Successfully!
```
A Telegram notification will then be sent: `✅ Oracle Cloud Ampere Instance successfully provisioned!`

The script exits after successful provisioning. This prevents unnecessary additional Apply jobs after the instance has been successfully created.

### Failed Provisioning
If the Resource Manager job fails or is canceled, the script will display:
```text
[DATE] Job Failed (Capacity Error). Waiting 3 minutes before next attempt...
```
The script then waits three minutes before submitting another Apply job. This process continues until provisioning succeeds.

### API / Rate-Limit Errors
If OCI does not return a valid Resource Manager Job OCID, the script treats the response as an API or rate-limit failure. It then waits five minutes:
```text
[DATE] Rate limit or API error detected. Cooling down for 5 minutes...
```
After the cooldown, another attempt is made.

---

## Running the Script Continuously

Once the script has been tested successfully, run it in the background:
```bash
nohup ./oci_loop.sh >> oci_loop.log 2>&1 &
```
The script will continue running after the SSH session is closed. The output is written to `oci_loop.log`.

---

## Verification and Monitoring

### 1. Monitor the Live Log
To watch the script in real time:
```bash
tail -f oci_loop.log
```
Press `Ctrl+C` to exit the log viewer. This does not stop the script.

### 2. Check Whether the Script Is Running
Run:
```bash
pgrep -af oci_loop.sh
```
Example output: `12345 /bin/bash ./oci_loop.sh`. If the command returns a process, the script is running. If there is no output, the script is not currently running.

### 3. Check the Resource Manager Job
When the script submits a job, it prints the Job OCID:
```text
[DATE] Submitted Job: ocid1.ormjob.oc1....
```
The job can be inspected manually:
```bash
oci resource-manager job get --job-id "JOB_OCID"
```
*(Replace `JOB_OCID` with the actual Job OCID.)*
Possible job states include: `ACCEPTED`, `IN_PROGRESS`, `SUCCEEDED`, `FAILED`, `CANCELED`.

### Verify the Compute Instance
After the Resource Manager job reaches `SUCCEEDED`, verify that the expected compute instance was created. You can list instances in the relevant compartment:
```bash
oci compute instance list --compartment-id "COMPARTMENT_OCID"
```
*(Replace `COMPARTMENT_OCID` with the OCID of the compartment containing the instance.)* You can also verify the instance directly through the OCI Console.

### Telegram Verification
After successful provisioning, the script sends `✅ Oracle Cloud Ampere Instance successfully provisioned!` to the configured Telegram chat. If the OCI Resource Manager job succeeds but the Telegram notification is not received, verify your Telegram Bot Token, Telegram Chat ID, network connectivity, and Telegram API availability. The Telegram notification is informational and does not determine whether OCI provisioning succeeded.

---

## Running 24/7

This script is designed to run continuously on an OCI compute instance or another Linux server. A typical deployment looks like:

```text
                 GitHub
                    |
                    | git clone
                    v
            Linux / OCI Server
                    |
                    v
              oci_loop.sh
                    |
                    v
           OCI Resource Manager
                    |
            +-------+-------+
            |               |
          FAILED          SUCCEEDED
            |               |
            v               v
        Wait 3 min     Telegram Alert
            |               |
            +---- Retry     Exit
```

To run continuously:
```bash
nohup ./oci_loop.sh >> oci_loop.log 2>&1 &
```
The server must remain powered on and connected to the network.

---

## Stopping the Script

Check the running process:
```bash
pgrep -af oci_loop.sh
```
Stop the script:
```bash
pkill -f oci_loop.sh
```
Verify it stopped:
```bash
pgrep -af oci_loop.sh
```
If nothing is returned, the script is no longer running.

---

## Updating the Script

If the repository is already deployed on an OCI server and a newer version is pushed to GitHub, update the local copy.

First stop the running script:
```bash
pkill -f oci_loop.sh
```
Go to the repository:
```bash
cd /path/to/REPOSITORY_NAME
```
Pull the latest version:
```bash
git pull
```
Make sure the script is executable:
```bash
chmod +x oci_loop.sh
```
Start it again:
```bash
nohup ./oci_loop.sh >> oci_loop.log 2>&1 &
```
Verify and monitor:
```bash
pgrep -af oci_loop.sh
tail -f oci_loop.log
```

---

## Important: Do Not Run Multiple Copies

Only run **one copy** of this script against the same Resource Manager Stack at a time. Running multiple copies simultaneously can result in overlapping Apply jobs and may cause OCI Resource Manager concurrency or authorization errors. 

Before starting the script, check:
```bash
pgrep -af oci_loop.sh
```
If an existing process is already running, do not start another copy.

---

## Retry Intervals

The script intentionally includes delays between operations.

| Situation | Delay |
| :--- | :--- |
| Resource Manager job status polling | 30 seconds |
| Failed or canceled Apply job | 3 minutes |
| Invalid Job OCID / API error | 5 minutes |

These delays help reduce unnecessary OCI API requests and avoid aggressive polling. Do not remove or drastically reduce these delays.

---

## Logs

The background process writes output to `oci_loop.log`. View the log:
```bash
tail -f oci_loop.log
```
Check the log size:
```bash
ls -lh oci_loop.log
```
If the log becomes large, it can be archived:
```bash
mv oci_loop.log oci_loop.log.old
```
Then restart the script:
```bash
nohup ./oci_loop.sh >> oci_loop.log 2>&1 &
```

---

## Security

The repository contains placeholders rather than real secrets. Never commit:
- Telegram Bot Tokens
- OCI API private keys
- OCI private SSH keys
- OCI configuration files containing credentials
- Other authentication secrets

Before committing changes, review the repository:
```bash
git status
git diff --cached
```
If the repository is public, make sure no real credentials are present before running:
```bash
git push
```
If a secret is accidentally committed, simply deleting it from the current file is not sufficient because it may remain in Git history. Revoke or rotate the exposed credential immediately and clean the Git history if necessary.

---

## Example Workflow

### First-Time Setup
```bash
git clone git@github.com:kiz01/REPOSITORY_NAME.git
cd REPOSITORY_NAME
nano oci_loop.sh
chmod +x oci_loop.sh
./oci_loop.sh
```
After confirming that everything works, stop the test if necessary and run it in the background:
```bash
nohup ./oci_loop.sh >> oci_loop.log 2>&1 &
pgrep -af oci_loop.sh
tail -f oci_loop.log
```

### Future Deployment
If you need to use this automation again on another Linux or OCI server:
```bash
git clone git@github.com:kiz01/REPOSITORY_NAME.git
cd REPOSITORY_NAME
nano oci_loop.sh
chmod +x oci_loop.sh
./oci_loop.sh
nohup ./oci_loop.sh >> oci_loop.log 2>&1 &
pgrep -af oci_loop.sh
tail -f oci_loop.log
```

---

## Repository Structure

The repository intentionally remains simple:
```text
.
├── README.md
└── oci_loop.sh
```
- `oci_loop.sh` contains the automation logic.
- `README.md` contains the installation, configuration, execution, monitoring, troubleshooting, and redeployment instructions.

---

## Disclaimer

This project is intended for personal OCI automation and experimentation. The script continuously attempts to provision the configured OCI resources until the Resource Manager operation succeeds. Use appropriate retry intervals and monitor OCI account activity, resource usage, and applicable OCI service limits.

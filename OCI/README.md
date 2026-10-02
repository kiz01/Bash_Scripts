# OCI Ampere A1 Auto-Provisioner

An automated bash script that continuously polls Oracle Cloud Infrastructure (OCI) to claim an "Always Free" ARM Ampere A1 compute instance in highly constrained regions (like Mumbai, Seoul, etc.). 

Because Oracle frequently runs out of hardware capacity for free-tier users, attempting to manually create an instance often results in an `Out of host capacity` error. This script utilizes OCI Resource Manager to automate the request process, safely handling API rate limits and pinging you on Telegram the moment your server is successfully provisioned.

## Features
- **Rate-Limit Aware:** Automatically detects `429 Too Many Requests` API limits and initiates a 5-minute cooldown to protect your account.
- **Telegram Integration:** Sends a push notification to your phone the second the server is provisioned.
- **Set & Forget:** Designed to run 24/7 in the background via `nohup` on a micro instance.
- **Graceful Exit:** Automatically shuts down once successful to prevent duplicate instances.

## Prerequisites
1. An Oracle Cloud Account.
2. The [OCI CLI](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm) installed and authenticated.
3. A pre-configured **Resource Manager Stack** in OCI set up to provision your desired Ampere instance.
4. A Telegram Bot Token and your personal Chat ID (from [@BotFather](https://core.telegram.org/bots)).


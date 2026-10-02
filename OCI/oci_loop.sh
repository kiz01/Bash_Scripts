#!/bin/bash

# ==============================================================================
# OCI Ampere A1 Auto-Provisioner
# ==============================================================================

STACK_ID="PASTE_YOUR_STACK_OCID_HERE"
BOT_TOKEN="PASTE_YOUR_BOT_TOKEN_HERE"
CHAT_ID="PASTE_YOUR_CHAT_ID_HERE"

echo "[$(date)] Starting Resource Manager Stack loop..."

while true; do
    echo "[$(date)] Triggering Apply job..."
    
    JOB_ID=$(oci resource-manager job create-apply-job \
        --stack-id "$STACK_ID" \
        --execution-plan-strategy AUTO_APPROVED \
        --query "data.id" \
        --raw-output 2>&1)

    # Validate that we received a real Job OCID (Handle Rate Limits)
    if [[ "$JOB_ID" != ocid1.ormjob* ]]; then
        echo "[$(date)] Rate limit or API error detected. Cooling down for 5 minutes..."
        sleep 300
        continue
    fi

    echo "[$(date)] Submitted Job: $JOB_ID"
    
    # Poll the job status every 30 seconds
    while true; do
        sleep 30
        STATUS=$(oci resource-manager job get --job-id "$JOB_ID" --query "data.\"lifecycle-state\"" --raw-output 2>&1)
        echo "[$(date)] Current Job Status: $STATUS"
        
        if [[ "$STATUS" == "SUCCEEDED" ]]; then
            echo "[$(date)] Instance Provisioned Successfully!"
            
            # Send Telegram Notification
            curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
                -d "chat_id=${CHAT_ID}" \
                -d "text=✅ Oracle Cloud Ampere Instance successfully provisioned!"
            
            # Exit cleanly
            exit 0
            
        elif [[ "$STATUS" == "FAILED" || "$STATUS" == "CANCELED" ]]; then
            echo "[$(date)] Job Failed (Capacity Error). Waiting 3 minutes before next attempt..."
            break
        fi
    done
    
    # Standard wait between attempts to avoid rate-limiting
    sleep 180
done

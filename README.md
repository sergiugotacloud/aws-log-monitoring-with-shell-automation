# Log Analyzer — Shell Script + AWS CloudWatch Alerting

A Bash script that scans log files for errors, saves a structured report, and alerts you when things go wrong. Built out of a real need — then taken a step further by deploying it on EC2 with CloudWatch metrics and SNS email notifications.

---

## The Problem

If you've ever worked in a DevOps or cloud engineering role, you know this situation: you've got a handful of services dumping logs into a directory, and every morning someone has to manually grep through them looking for errors. It's repetitive, easy to miss things, and honestly just a waste of time.

That was the starting point here. What used to take 30–45 minutes of manual command execution per day — checking for `ERROR`, `FATAL`, and `CRITICAL` entries across multiple log files — now runs in seconds with a single command.

---

## What It Does

- Scans only the log files modified in the **last 24 hours** (no need to re-check unchanged files)
- Searches for configurable error patterns (`ERROR`, `FATAL`, `CRITICAL`)
- Counts occurrences per pattern per file
- Saves a structured report to a `.txt` file
- Fires an **ALERT** to stdout if any pattern exceeds your defined threshold
- Portable — point it at any log directory by changing two variables at the top

---

## Script

```bash
#!/bin/bash

# =========================
# CONFIGURATION
# =========================
LOG_DIR="/home/ec2-user/logs"
REPORT_FILE="/home/ec2-user/logs/log_analysis_report.txt"
ERROR_PATTERNS=("ERROR" "FATAL" "CRITICAL")
THRESHOLD=10

# =========================
# INIT REPORT
# =========================
echo "Log Analysis Report" > "$REPORT_FILE"
echo "======================" >> "$REPORT_FILE"

echo -e "\nLog files modified in last 24h:" >> "$REPORT_FILE"
LOG_FILES=$(find "$LOG_DIR" -name "*.log" -mtime -1)
echo "$LOG_FILES" >> "$REPORT_FILE"

# =========================
# PROCESS LOG FILES
# =========================
for LOG_FILE in $LOG_FILES; do

    echo -e "\n===================================" >> "$REPORT_FILE"
    echo "Processing: $LOG_FILE" >> "$REPORT_FILE"
    echo "===================================" >> "$REPORT_FILE"

    for PATTERN in "${ERROR_PATTERNS[@]}"; do

        echo -e "\nChecking: $PATTERN" >> "$REPORT_FILE"

        # Print matching lines
        grep "$PATTERN" "$LOG_FILE" >> "$REPORT_FILE"

        # Count occurrences
        COUNT=$(grep -c "$PATTERN" "$LOG_FILE")
        echo "Count: $COUNT" >> "$REPORT_FILE"

        # ALERT LOGIC
        if [ "$COUNT" -gt "$THRESHOLD" ]; then
            echo "WARNING: High number of $PATTERN in $LOG_FILE" >> "$REPORT_FILE"
            echo "ALERT: $PATTERN issue detected in $LOG_FILE"
        fi

    done

done

# =========================
# FINAL OUTPUT
# =========================
echo -e "\nLog analysis completed."
echo "Report saved at: $REPORT_FILE"
```

---

## How to Use It

### 1. Clone or copy the script

```bash
curl -O https://raw.githubusercontent.com/your-repo/analyze-logs.sh
# or just copy the script above into a file
```

### 2. Edit the configuration block

Open the script and update the top section:

```bash
LOG_DIR="/path/to/your/logs"           # where your .log files live
REPORT_FILE="/path/to/report.txt"      # where you want the output saved
ERROR_PATTERNS=("ERROR" "FATAL" "CRITICAL")  # patterns to search for
THRESHOLD=10                           # alert if count exceeds this
```

### 3. Make it executable and run

```bash
chmod +x analyze-logs.sh
./analyze-logs.sh
```

### 4. Check the output

The script prints a summary to the terminal and saves the full report:

```
Log analysis completed.
Report saved at: /home/ec2-user/logs/log_analysis_report.txt
```

And inside the report:

```
Processing: /home/ec2-user/logs/application.log
===================================

Checking: ERROR
ERROR: payment failed
Count: 1

Checking: FATAL
FATAL: database down
Count: 1

Checking: CRITICAL
Count: 0
```

If a threshold is crossed, you'll see this in stdout:

```
ALERT: ERROR issue detected in /home/ec2-user/logs/system.log
```

### 5. Automate it with cron (optional)

Run it every day at 8am without touching it again:

```bash
crontab -e
# Add this line:
0 8 * * * /home/ec2-user/analyze-logs.sh
```

---

## Taking It to AWS — EC2 + CloudWatch + SNS

After getting the script working locally, the next logical step was deploying it on a real server and adding proper alerting through AWS. Here's how the setup looks:

### Infrastructure

- **EC2** — Amazon Linux 2023, t3.micro (eu-central-1)
- **CloudWatch Logs** — script output streamed to a log group called `log-analyzer`, with two log streams: `application` and `system`
- **CloudWatch Metric Filter** — watches for the string `ERROR` and increments a custom metric (`LogAnalyzer/ErrorCW`) every time it appears
- **CloudWatch Alarm** — triggers when `ErrorCW > 5` in a 1-minute window
- **SNS Topic** — alarm fires a notification to `log-alerts`, which sends an email

### How to Deploy on EC2

**Step 1 — Launch an EC2 instance**

Any Amazon Linux 2023 t3.micro will do. Make sure you attach an IAM role with `CloudWatchAgentServerPolicy` or equivalent permissions to push logs.

**Step 2 — SSH in and set up your log directory**

```bash
ssh -i YOURKEYPAIR.pem ec2-user@YOUR_EC2_IP
mkdir -p ~/logs
```

**Step 3 — Copy the script and make it executable**

```bash
# Upload from local
scp -i YOURKEYPAIR.pem analyze-logs.sh ec2-user@YOUR_EC2_IP:~/

# Or create it directly on the instance
nano ~/analyze-logs.sh
chmod +x ~/analyze-logs.sh
```

**Step 4 — Install and configure the CloudWatch Agent**

```bash
sudo dnf install amazon-cloudwatch-agent -y
```

Create a basic agent config at `/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json`:

```json
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/home/ec2-user/logs/application.log",
            "log_group_name": "log-analyzer",
            "log_stream_name": "application"
          },
          {
            "file_path": "/home/ec2-user/logs/system.log",
            "log_group_name": "log-analyzer",
            "log_stream_name": "system"
          }
        ]
      }
    }
  }
}
```

Start the agent:

```bash
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
```

**Step 5 — Create a Metric Filter in CloudWatch**

In the AWS Console, go to **CloudWatch → Log groups → log-analyzer → Metric filters → Create metric filter**:

- Filter pattern: `ERROR`
- Metric namespace: `LogAnalyzer`
- Metric name: `ErrorCW`
- Metric value: `1`

**Step 6 — Create the Alarm**

Go to **CloudWatch → Alarms → Create alarm**:

- Select metric: `LogAnalyzer → ErrorCW`
- Threshold: `Greater than 5` for `1 out of 1` datapoints (1-minute period)
- Action: send to an SNS topic (create one if you don't have it, subscribe your email)

Once set up, if you inject 12+ errors into a log file and run the script, the alarm will fire within a minute and you'll get an email from `no-reply@sns.amazonaws.com`.

---

## Screenshots

| Step | Description |
|------|-------------|
| EC2 instance running | t3.micro `log-analyzer` in eu-central-1 |
| SSH connection | Amazon Linux 2023 terminal access |
| Script execution | `./analyze-logs.sh` running on the instance |
| Report output | Structured breakdown by file and pattern |
| Alert trigger | 12 injected ERRORs trigger the ALERT stdout message |
| CloudWatch log group | `log-analyzer` with `system` and `application` streams |
| Metric filter | `ErrorCount` filter → `LogAnalyzer/ErrorCW` metric |
| Alarm in alarm state | `ErrorCW > 5` threshold breached |
| SNS email | Email notification fired from `sns.amazonaws.com` |

---

## Customisation

The script is intentionally simple so you can adapt it. A few things you might want to change:

- **Add more error patterns** — just extend the `ERROR_PATTERNS` array
- **Change the time window** — swap `-mtime -1` for `-mtime -2` to look back 2 days
- **Send alert via email locally** — pipe the ALERT output to `mail` or `sendmail`
- **Push to Slack** — replace the `echo "ALERT..."` line with a `curl` call to a webhook
- **Adjust the threshold** — lower it during incidents, raise it for noisy services

---

## Requirements

- Bash 4+ (standard on Amazon Linux, macOS requires `brew install bash`)
- Standard Linux tools: `find`, `grep` — nothing exotic
- For the AWS extension: an EC2 instance, IAM permissions for CloudWatch, and the CloudWatch Agent installed

---

## Why This Matters

This started as a manual process that ate up time every day. Turning it into a script was the first win. Deploying it on EC2 and wiring it to CloudWatch + SNS was the second — now errors surface as email alerts rather than requiring anyone to remember to run a command.

It's a small project, but it's the kind of automation that actually changes how a team operates day-to-day.

---

*Built by Sergiu Gota — [Gota Labs](https://gotalabs.io)*

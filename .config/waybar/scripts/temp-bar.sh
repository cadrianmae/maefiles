#!/bin/bash
# CPU & GPU temperature with enhanced tooltip

# CPU temp
cpu_temp=$(sensors coretemp-isa-0000 2>/dev/null | awk '/Package id 0:/ {gsub(/[+°C]/,""); print $4}')
cpu_temp=${cpu_temp%.*}

# Per-core temps for tooltip
core_temps=$(sensors coretemp-isa-0000 2>/dev/null | awk '/Core [0-9]:/ {gsub(/[+°C]/,""); printf "  Core %s: %s°C\\n", $2, $3}')

# GPU temp (NVIDIA)
gpu_info=$(nvidia-smi --query-gpu=temperature.gpu,utilization.gpu,memory.used,memory.total,name --format=csv,noheader 2>/dev/null)
if [ -n "$gpu_info" ]; then
    gpu_temp=$(echo "$gpu_info" | cut -d',' -f1 | tr -d ' ')
    gpu_util=$(echo "$gpu_info" | cut -d',' -f2 | tr -d ' ')
    gpu_mem_used=$(echo "$gpu_info" | cut -d',' -f3 | tr -d ' ')
    gpu_mem_total=$(echo "$gpu_info" | cut -d',' -f4 | tr -d ' ')
    gpu_name=$(echo "$gpu_info" | cut -d',' -f5 | tr -d ' ' | sed 's/NVIDIAGeForce//')
else
    gpu_temp="N/A"
    gpu_util="N/A"
    gpu_mem_used="N/A"
    gpu_mem_total="N/A"
    gpu_name="N/A"
fi

# Determine alert class
max_temp=$cpu_temp
[ "$gpu_temp" != "N/A" ] && [ "$gpu_temp" -gt "$max_temp" ] 2>/dev/null && max_temp=$gpu_temp

if [ "$max_temp" -ge 85 ]; then
    alert="critical"
elif [ "$max_temp" -ge 70 ]; then
    alert="warning"
else
    alert=""
fi

# Build tooltip
tooltip=" CPU: ${cpu_temp}°C\\n${core_temps}\\n󰢮 GPU: ${gpu_temp}°C (${gpu_name})\\n  Usage: ${gpu_util}\\n  VRAM: ${gpu_mem_used} / ${gpu_mem_total}"

# Display text - show both temps (spaces around icons)
text="  ${cpu_temp}°   󰢮  ${gpu_temp}°"

echo "{\"text\": \"$text\", \"tooltip\": \"$tooltip\", \"class\": \"$alert\"}"

#!/system/bin/sh
echo "=== A. tracerfs mounté ? ==="
mount | grep -i tracefs | head
ls /sys/kernel/tracing/trace 2>/dev/null && echo "tracer dispo" || echo "pas de tracer"
echo "=== B. events fastrpc dispo ? ==="
ls /sys/kernel/tracing/events/fastrpc/ 2>/dev/null
echo "=== C. fastrpc-nsp1000 sysfs ==="
ls /sys/devices/virtual/misc/fastrpc-nsp1000/ 2>/dev/null
cat /sys/devices/virtual/misc/fastrpc-nsp1000/uevent 2>/dev/null
echo "=== D. compteur IRQ CDSP sur 2 fenêtres (0.5s) ==="
c1=$(grep -E 'smp2p-cdsp' /proc/interrupts | awk '{s+=$2} END{print s}')
sleep 0.5
c2=$(grep -E 'smp2p-cdsp' /proc/interrupts | awk '{s+=$2} END{print s}')
echo "cdsp_irq_delta=$((c2-c1))"
echo "=== E. fastrpc tracepoint (1s de comptage) ==="
echo "0" > /sys/kernel/tracing/tracing_on 2>/dev/null
echo "fastrpc" > /sys/kernel/tracing/current_tracer 2>/dev/null
echo "fastrpc_dspsignal" > /sys/kernel/tracing/set_event 2>/dev/null
echo "1" > /sys/kernel/tracing/tracing_on 2>/dev/null
sleep 1
echo "0" > /sys/kernel/tracing/tracing_on 2>/dev/null
n=$(grep -c 'fastrpc_dspsignal' /sys/kernel/tracing/trace 2>/dev/null)
echo "fastrpc_dspsignal_count_1s=$n"
echo "0" > /sys/kernel/tracing/set_event 2>/dev/null
echo "=== F. cdsprpcd cpu% (process) ==="
top -n 1 -b 2>/dev/null | grep -i cdsprpcd | head
#!/system/bin/sh
echo "=== SUITE DECOUVERTES ==="
logcat -d 2>/dev/null | grep -iE "GenieXSdk.*(H[0-9]|Statut|Impact|Conclusion|Script|CONFIRMED|CANDIDATE|DISPROVEN|SUSPECTED|dma_buf|IOMMU|GenieX|QAIRT|kernel|FastRPC|find_vma|vma_lookup)" | tail -50

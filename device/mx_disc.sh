#!/system/bin/sh
echo "=== DECOUVERTES COMPLETES ==="
logcat -d 2>/dev/null | grep -iE "GenieXSdk.*(H[0-9]|Statut|CONFIRMED|CANDIDATE|DISPROVEN|SUSPECTED|Impact|Conclusion|Script|Risque|FastRPC|find_vma|vma_lookup|dma_buf|IOMMU|GenieX|QAIRT|kernel)" | tail -40

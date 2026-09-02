#!/system/bin/sh
echo "=== DECOUVERTES LLM COMPLETES ==="
logcat -d 2>/dev/null | grep -iE "GenieXSdk.*(H[0-9]|CONFIRMED|CANDIDATE|DISPROVEN|SUSPECTED|Statut|Risque|FastRPC|find_vma|vma_lookup|dma_buf|IOMMU|GenieX|QAIRT|kernel|Script|Conclusion|Impact)" | tail -60

#!/system/bin/sh
echo "=== SUITE DECOUVERTES (H1+ et conclusion) ==="
logcat -d 2>/dev/null | grep -iE "GenieXSdk.*(H[0-9]|\[F\]|\[S\]|\[D\]|\[I\]|\[H\]|Statut|CONFIRMED|CANDIDATE|DISPROVEN|SUSPECTED|Impact|Conclusion|Script|Risque|FastRPC|find_vma|vma_lookup|dma_buf|IOMMU|GenieX|QAIRT|kernel|QNN)" | tail -45

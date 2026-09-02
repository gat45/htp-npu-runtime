for p in com.google.android.apps.walletnfcrel com.google.android.gms com.android.vending com.op15.remoteaccess; do magisk --denylist add $p 2>/dev/null; done
echo --- denylist ---
magisk --denylist ls
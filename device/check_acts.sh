#!/system/bin/sh
dumpsys package com.op15.toolkit | grep -E "com\.op15\.toolkit\.(terminal|remote|server|opencode)" | head -12
util = require 'util'
cqueues = require 'cqueues'
moduleName = 'systemd-watchdog'
queue = cqueues.running()

-- 1. Signal that the bot has finished loading
os.execute 'systemd-notify --ready'

queue\wrap ->
	while true
		ok, err = pcall ->
			cqueues.sleep(30)
			os.execute 'systemd-notify WATCHDOG=1'
			ivar2\Log 'debug', "#{moduleName}: Watchdog ping!"
		if not ok
			ivar2\Log 'error', "#{moduleName}: Error #{err}"
			continue
		if err and err != 0
			ivar2\Log 'error', "#{moduleName}: Error #{err}"
			continue
globals = {'ivar2', 'say', 'reply', 'setfenv',}
unused_args = false
std = "lua51"
files["modules/**/*_spec.lua"] = {
	std = "+busted";
	new_globals = {
		"TEST_TIMEOUT";
		"assert_loop";
	};
}
files["spec"] = {
	std = "+busted";
	new_globals = {
		"TEST_TIMEOUT";
		"assert_loop";
	};
}

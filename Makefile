test:
	nvim --headless -u tests/minimal_init.lua -c "lua dofile('tests/hello.lua')"

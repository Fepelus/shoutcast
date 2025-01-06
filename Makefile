compile:
	zig build-exe ./src/main.zig

cross-compile:
	zig build-exe ./src/main.zig --name shoutcast -O ReleaseSmall -fstrip -target arm-linux

install: cross-compile
	scp shoutcast paddy@pi:/usr/local/bin/shoutcast
	ssh paddy@pi mv /usr/local/bin/shoutcast /usr/local/bin/shoutcast.zig

CC = x86_64-w64-mingw32-gcc
CFLAGS = -shared -Wall -O2
DEARXAN_DIR = dearxan
INCLUDES = -I$(DEARXAN_DIR)/include -Isrc
LDFLAGS = -L$(DEARXAN_DIR)/target/x86_64-pc-windows-gnu/release -ldearxan \
          -lws2_32 -luserenv -ldbghelp -lntdll \
          -static-libgcc
TARGET = DINPUT8.dll
SRC = ./src/*.c
APP_ID = 570940

AES_DIR = lib/tiny-AES-c
DECRYPT_TARGET = decrypt
DECRYPT_SRC = src/decrypt.c $(AES_DIR)/aes.c
DECRYPT_INCLUDES = -I$(AES_DIR) -Isrc

build: $(SRC)
	$(CC) $(CFLAGS) $(INCLUDES) -o $(TARGET) $(SRC) $(LDFLAGS)

decrypt: $(DECRYPT_SRC)
	gcc -Wall -O2 $(DECRYPT_INCLUDES) -o $(DECRYPT_TARGET) $(DECRYPT_SRC)

install: build
	cp $(TARGET) ~/.local/share/Steam/steamapps/common/DARK\ SOULS\ REMASTERED/
	if pgrep DarkSoulsRemas; then pkill DarkSoulsRemas; fi
	steam steam://rungameid/$(APP_ID)
	hyprctl dispatch focusworkspaceoncurrentmonitor 5

uninstall:
	rm -f ~/.local/share/Steam/steamapps/common/DARK\ SOULS\ REMASTERD/$(TARGET)

clean:
	rm -f $(TARGET) $(DECRYPT_TARGET)

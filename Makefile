APP_PATH = /Applications/dLive Director V2.11.app
QTPATH = $(APP_PATH)/Contents/Frameworks
BINARY = $(APP_PATH)/Contents/MacOS/dLive Director V2.11
QTHDR = /opt/homebrew/Cellar/qt@5/5.15.17/lib

CXX = clang++
CFLAGS = -arch x86_64 -std=c++17 -ObjC++ -c \
  -iframework "$(QTHDR)" \
  -I"$(QTHDR)/QtCore.framework/Headers" \
  -I"$(QTHDR)/QtWidgets.framework/Headers" \
  -I"$(QTHDR)/QtGui.framework/Headers"

LDFLAGS = -arch x86_64 -dynamiclib \
  -F"$(QTPATH)" \
  -framework QtCore \
  -framework QtWidgets \
  -framework QtGui \
  -framework Foundation \
  -framework AppKit \
  -rpath "$(QTPATH)"

TARGET = libmovechannel.dylib
SOURCES = src/plugin_main.mm
OBJECTS = plugin_main.o

all: $(TARGET)

plugin_main.o: $(SOURCES)
	$(CXX) $(CFLAGS) -o $@ $<

$(TARGET): $(OBJECTS)
	$(CXX) $(LDFLAGS) -o $@ $^

clean:
	rm -f $(TARGET) $(OBJECTS)

run: $(TARGET)
	DYLD_INSERT_LIBRARIES="$(PWD)/$(TARGET)" "$(BINARY)"

.PHONY: all clean run

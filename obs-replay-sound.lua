local obs = obslua
local ffi = require("ffi")

ffi.cdef [[
    typedef struct SDL_AudioStream SDL_AudioStream;
    typedef uint32_t               SDL_AudioDeviceID;
    typedef int                    SDL_AudioFormat;

    typedef struct SDL_AudioSpec {
        SDL_AudioFormat format;
        int             channels;
        int             freq;
    } SDL_AudioSpec;

    bool        SDL_SetHint  (const char *name, const char *value);
    bool        SDL_Init     (uint32_t flags);
    void        SDL_Quit     (void);
    const char *SDL_GetError (void);
    void        SDL_free     (void *mem);

    bool SDL_LoadWAV(
        const char     *path,
        SDL_AudioSpec  *spec,
        uint8_t       **audio_buf,
        uint32_t       *audio_len
    );

    SDL_AudioStream *SDL_OpenAudioDeviceStream(
        SDL_AudioDeviceID    devid,
        const SDL_AudioSpec *spec,
        void                *callback,
        void                *userdata
    );

    bool SDL_PutAudioStreamData      (SDL_AudioStream *stream, const void *buf, int len);
    bool SDL_ClearAudioStream        (SDL_AudioStream *stream);
    bool SDL_ResumeAudioStreamDevice (SDL_AudioStream *stream);
    bool SDL_SetAudioStreamGain      (SDL_AudioStream *stream, float gain);
    void SDL_DestroyAudioStream      (SDL_AudioStream *stream);
]]

local SDL_INIT_AUDIO                    = 0x00000010
local SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK = 0xFFFFFFFF
local SDL_LIBRARY_NAMES                 = {
    Windows = { "SDL3.dll" },
    OSX     = { "libSDL3.dylib", "/opt/homebrew/lib/libSDL3.dylib", "/usr/local/lib/libSDL3.dylib" },
    Linux   = { "libSDL3.so.0", "libSDL3.so" },
}

local SDL        = nil
local stream     = nil
local sound      = { buffer = nil, length = 0, path = nil }
local sound_path = ""
local volume     = 1.0

local function sdl_error()
    return ffi.string(SDL.SDL_GetError())
end

local LOG_LEVELS = {
    error = obs.LOG_ERROR,
    warn  = obs.LOG_WARNING,
    info  = obs.LOG_INFO,
    debug = obs.LOG_DEBUG,
}

local function log(level, msg, ...)
    local obs_level = LOG_LEVELS[level]

    if obs_level == nil then
        error("unknown log level '" .. tostring(level) .. "' (use error, warn, info, or debug)", 2)
    end

    if select("#", ...) > 0 then
        msg = string.format(msg, ...)
    end

    obs.script_log(obs_level, msg)
end

local function library_candidates()
    local names      = SDL_LIBRARY_NAMES[ffi.os] or SDL_LIBRARY_NAMES.Linux
    local candidates = {}

    for _, name in ipairs(names) do
        if not name:find("/", 1, true) then
            table.insert(candidates, script_path() .. name)
        end
    end

    for _, name in ipairs(names) do
        table.insert(candidates, name)
    end

    return candidates
end

local function load_sdl()
    for _, path in ipairs(library_candidates()) do
        local ok, lib = pcall(ffi.load, path)

        if ok then
            SDL = lib
            log("info", "loaded SDL3 from %s", path)
            break
        end
    end

    if not SDL then
        log("error", "could not find SDL3 (put it next to this script or install it system-wide)")
        return false
    end

    SDL.SDL_SetHint("SDL_NO_SIGNAL_HANDLERS", "1")

    if not SDL.SDL_Init(SDL_INIT_AUDIO) then
        log("error", "SDL_Init failed: %s", sdl_error())
        SDL = nil
        return false
    end

    return true
end

local function unload_sound()
    if stream ~= nil then
        SDL.SDL_DestroyAudioStream(stream)
        stream = nil
    end

    if sound.buffer ~= nil then
        SDL.SDL_free(sound.buffer)
        sound.buffer = nil
        sound.length = 0
    end
end

local function load_sound(path)
    unload_sound()

    if path == "" then
        return true
    end

    local spec   = ffi.new("SDL_AudioSpec[1]")
    local buffer = ffi.new("uint8_t*[1]")
    local length = ffi.new("uint32_t[1]")

    if not SDL.SDL_LoadWAV(path, spec, buffer, length) then
        log("warn", "could not load %s: %s", path, sdl_error())
        return false
    end

    sound.buffer = buffer[0]
    sound.length = length[0]

    stream = SDL.SDL_OpenAudioDeviceStream(SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, spec, nil, nil)

    if stream == nil then
        log("error", "could not open audio device: %s", sdl_error())
        unload_sound()
        return false
    end

    SDL.SDL_SetAudioStreamGain(stream, volume)
    SDL.SDL_ResumeAudioStreamDevice(stream)

    log("info", "loaded %s (%d Hz, %d ch)", path, spec[0].freq, spec[0].channels)

    return true
end

local function apply_settings()
    if not SDL then
        return
    end

    if sound_path ~= sound.path then
        sound.path = load_sound(sound_path) and sound_path or nil
    end

    if stream ~= nil then
        SDL.SDL_SetAudioStreamGain(stream, volume)
    end
end

local function play_sound()
    if stream == nil then
        return
    end

    SDL.SDL_ClearAudioStream(stream)
    SDL.SDL_PutAudioStreamData(stream, sound.buffer, sound.length)
end

local function on_frontend_event(event)
    if event == obs.OBS_FRONTEND_EVENT_REPLAY_BUFFER_SAVING then
        play_sound()
    end
end

function script_description()
    return "Play a sound when you save a replay. Only WAV files are supported."
end

function script_properties()
    local props         = obs.obs_properties_create()
    local volume_slider = obs.obs_properties_add_int_slider(props, "volume_percent", "Volume", 0, 100, 1)

    obs.obs_property_int_set_suffix(volume_slider, "%")
    obs.obs_properties_add_path(props, "sound_path", "Sound file", obs.OBS_PATH_FILE, "WAV files (*.wav)", nil)
    obs.obs_properties_add_button(props, "test", "Test sound", function() play_sound() return false end)

    return props
end

function script_defaults(settings)
    obs.obs_data_set_default_int(settings, "volume_percent", 100)
end

function script_update(settings)
    volume     = (obs.obs_data_get_int(settings, "volume_percent") / 100) ^ 2
    sound_path = obs.obs_data_get_string(settings, "sound_path")

    apply_settings()
end

function script_load(settings)
    if load_sdl() then
        script_update(settings)
        obs.obs_frontend_add_event_callback(on_frontend_event)
    end
end

function script_unload()
    if not SDL then
        return
    end

    unload_sound()
    SDL.SDL_Quit()

    SDL        = nil
    sound.path = nil
end

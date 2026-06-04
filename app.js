const express = require("express");
const cors = require("cors");
const axios = require("axios");
const { initTLS } = require('node-tls-client');
const { getRiveStreams, getRiveRawResponse, processRiveResponse } = require("./providers/rive.provider.js");
const { getWebstreamerStreams, getWebstreamerRawResponse } = require("./providers/webstreamer.provider.js");
const { getBaseUrl } = require("./providers/base-url.utility.js");
const { getShowboxStreams } = require("./providers/showbox.provider.js");
const { getCinemaOSStream, getMovieBoxStream, getFuckItStream } = require("./providers/cinemaos.provider.js");
const { getVidRockStreams, getVidRockRawResponse } = require("./providers/vidrock.provider.js");
const { getChallengeStreams, getChallengeRawResponse } = require("./providers/challenge.provider.js");
const { getPikashowStreams } = require("./providers/pikashow.provider.js");
const { getVidluxStreams, getVidluxRawResponse } = require("./providers/vidlux.provider.js");
const animeProvider = require("./providers/anime.provider.js");

const RIVE_SERVERS = ["flowcast", "asiacloud", "hindicast", "guru"];

const TMDB_KEYS = [
    "20bea604243a8f99322f925df8f3feab",
    "21a1ee435e06a7b9a089fe6e66b488ed",
    // Add more keys here
];

const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");
const { getPool } = require("./providers/db.utility.js");
const NodeCache = require("node-cache");

const JWT_SECRET = "streamflix-ultra-secret-2026";
const userCache = new NodeCache({ stdTTL: 600, checkperiod: 120 }); // 10 min cache




const http = require("http");
const app = express();
const server = http.createServer(app);
// const io = require("socket.io")(server, {
//     cors: { origin: "*" }
// });


const port = process.env.PORT || 7860;

app.use(cors());
app.use(express.json());




/**
 * Authentication Middleware
 */
async function authenticateToken(req, res, next) {
    const authHeader = req.headers['authorization'];
    const token = authHeader && authHeader.split(' ')[1];

    if (!token) return res.status(401).json({ error: "Access denied. Token missing." });

    try {
        const decoded = jwt.verify(token, JWT_SECRET);
        req.user = decoded;
        next();
    } catch (err) {
        res.status(403).json({ error: "Invalid or expired token." });
    }
}

// --- Auth Routes ---
app.post("/api/auth/signup", async (req, res) => {
    const { username, name, email, password } = req.body;
    if (!username || !name || !email || !password) {
        return res.status(400).json({ error: "All fields are required" });
    }

    try {
        const pool = await getPool();
        const hashedPassword = await bcrypt.hash(password, 10);
        
        const [result] = await pool.query(
            "INSERT INTO users (username, name, email, password) VALUES (?, ?, ?, ?)",
            [username, name, email, hashedPassword]
        );

        const token = jwt.sign({ id: result.insertId, email }, JWT_SECRET, { expiresIn: '30d' });
        res.status(201).json({ message: "User created", token, user: { id: result.insertId, username, email } });
    } catch (err) {
        if (err.code === 'ER_DUP_ENTRY') return res.status(400).json({ error: "Email already exists" });
        console.error("[Auth] Signup error:", err);
        res.status(500).json({ error: "Signup failed" });
    }
});

app.post("/api/auth/login", async (req, res) => {
    const { email, password } = req.body;
    if (!email || !password) return res.status(400).json({ error: "Email and password required" });

    try {
        const pool = await getPool();
        const [users] = await pool.query("SELECT * FROM users WHERE email = ?", [email]);
        const user = users[0];

        if (!user || !(await bcrypt.compare(password, user.password))) {
            return res.status(401).json({ error: "Invalid credentials" });
        }

        const token = jwt.sign({ id: user.id, email: user.email }, JWT_SECRET, { expiresIn: '30d' });
        res.json({ token, user: { id: user.id, username: user.username, email: user.email } });
    } catch (err) {
        console.error("[Auth] Login error:", err);
        res.status(500).json({ error: "Login failed" });
    }
});

// --- Sync Routes ---
const SYNC_TABLES = {
    history: 'watch_history',
    bookmarks: 'bookmarks',
    progress: 'series_progress',
    collections: 'media_collections',
    settings: 'app_settings',
    'music/playlists': 'music_playlists',
    'music/history': 'music_history'
};

// Helper to merge existing sync data with incoming additions
function mergeSyncData(existing, incoming) {
    if (existing === undefined || existing === null) return incoming;

    let parsedExisting = existing;
    if (typeof parsedExisting === 'string') {
        try {
            parsedExisting = JSON.parse(parsedExisting);
        } catch (e) {}
    }

    let parsedIncoming = incoming;
    if (typeof parsedIncoming === 'string') {
        try {
            parsedIncoming = JSON.parse(parsedIncoming);
        } catch (e) {}
    }

    // If existing is an array, merge them
    if (Array.isArray(parsedExisting)) {
        const merged = [...parsedExisting];
        const incomingArray = Array.isArray(parsedIncoming) ? parsedIncoming : [parsedIncoming];

        for (const item of incomingArray) {
            const getItemKey = (x) => x?.id || x?.tmdbId || x?.slug || x?.title;
            const itemKey = getItemKey(item);

            if (itemKey !== undefined && itemKey !== null) {
                const idx = merged.findIndex(x => getItemKey(x) === itemKey);
                if (idx !== -1) {
                    merged[idx] = typeof item === 'object' && item !== null && typeof merged[idx] === 'object'
                        ? { ...merged[idx], ...item }
                        : item;
                } else {
                    merged.push(item);
                }
            } else {
                if (!merged.some(x => JSON.stringify(x) === JSON.stringify(item))) {
                    merged.push(item);
                }
            }
        }
        return merged;
    }

    // If both are objects, merge keys
    if (typeof parsedExisting === 'object' && parsedExisting !== null && typeof parsedIncoming === 'object' && parsedIncoming !== null) {
        return { ...parsedExisting, ...parsedIncoming };
    }

    // Default fallback
    return parsedIncoming;
}

// Generic Sync GET
const handleSyncGet = async (req, res) => {
    const type = req.params.type || "";
    const tableName = SYNC_TABLES[type];
    if (!tableName && type !== "") return res.status(404).json({ error: "Invalid sync type" });

    try {
        const userId = req.user.id;
        const cacheKey = `sync_${userId}_${type || 'all'}`;
        
        const cached = userCache.get(cacheKey);
        if (cached) return res.json(cached);

        const pool = await getPool();
        if (type === "") {
            // Fetch all data
            const results = {};
            for (const [key, table] of Object.entries(SYNC_TABLES)) {
                const [rows] = await pool.query(`SELECT data FROM ${table} WHERE user_id = ?`, [userId]);
                const responseKey = key === 'music/history' ? 'music_history' : (key.includes('/') ? key.split('/').pop() : key);
                results[responseKey] = rows[0]?.data || (key.includes('progress') ? {} : []);
            }
            userCache.set(cacheKey, results);
            return res.json(results);
        }

        const [rows] = await pool.query(`SELECT data FROM ${tableName} WHERE user_id = ?`, [userId]);
        const data = rows[0]?.data || (tableName.includes('progress') ? {} : []);
        
        userCache.set(cacheKey, data);
        res.json(data);
    } catch (err) {
        console.error(`[Sync] GET ${type} error:`, err);
        res.status(500).json({ error: "Failed to fetch sync data" });
    }
};

app.get("/api/sync", authenticateToken, handleSyncGet);
app.get("/api/sync/:type(*)", authenticateToken, handleSyncGet);

// Generic Sync POST
app.post("/api/sync/:type(*)", authenticateToken, async (req, res) => {
    const type = req.params.type;
    const tableName = SYNC_TABLES[type];
    const data = req.body[type.split('/').pop()] || req.body.data;

    if (!tableName || data === undefined || data === null) return res.status(400).json({ error: "Invalid sync type or missing data" });

    try {
        const userId = req.user.id;
        const pool = await getPool();

        // Fetch existing data
        const [rows] = await pool.query(`SELECT data FROM ${tableName} WHERE user_id = ?`, [userId]);
        const existingData = rows[0]?.data;

        // Merge existing and incoming data
        const mergedData = mergeSyncData(existingData, data);
        
        await pool.query(
            `INSERT INTO ${tableName} (user_id, data) VALUES (?, ?) ON DUPLICATE KEY UPDATE data = ?, updated_at = CURRENT_TIMESTAMP`,
            [userId, JSON.stringify(mergedData), JSON.stringify(mergedData)]
        );

        userCache.del(`sync_${userId}_${type}`);
        userCache.del(`sync_${userId}_all`);
        res.json({ success: true, message: `${type} synced`, data: mergedData });
    } catch (err) {
        console.error(`[Sync] POST ${type} error:`, err);
        res.status(500).json({ error: "Failed to sync data" });
    }
});

/**
 * URL Validator
 * Checks if a URL is active, determines its content type and file size.
 */
async function validateUrl(stream) {
    if (!stream || !stream.url) return { isValid: false, contentType: null, size: 0 };
    try {
        const headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36'
        };
        if (stream.referer) headers['Referer'] = stream.referer;
        if (stream.origin) headers['Origin'] = stream.origin;

        // Try HEAD request first for speed and bandwidth efficiency
        let response;
        try {
            response = await axios.head(stream.url, {
                headers,
                timeout: 10000,
            });
        } catch (headErr) {
            // Fallback to GET if HEAD is not supported or fails
            response = await axios.get(stream.url, {
                headers,
                timeout: 15000,
                responseType: 'stream'
            });
        }
        
        const contentType = response.headers['content-type'] || "";
        const size = parseInt(response.headers['content-length'] || "0");
        
        // If it was a GET request with stream, destroy it
        if (response.data && typeof response.data.destroy === 'function') {
            response.data.destroy();
        }

        return { 
            isValid: response.status >= 200 && response.status < 400, 
            contentType: contentType.toLowerCase(),
            size: size
        };
    } catch (e) {
        return { isValid: false, contentType: null, size: 0 };
    }
}


app.get("/api/media/:index/:type", async (req, res) => {
    const { index, type } = req.params;
    const { id: tmdbId, season = "", episode = "" } = req.query;

    if (!tmdbId) {
        return res.status(400).json({ error: "Missing tmdbId (id) query parameter" });
    }

    try {
        const streamCacheKey = `streams_${index}_${type}_${tmdbId}_${season}_${episode}`;
        /*
        const cachedStreams = streamCache.get(streamCacheKey);
        if (cachedStreams) {
            console.log(`[Cache] Stream Hit: ${streamCacheKey}`);
            return res.json(cachedStreams);
        }
        */

        let responseData;

        if (index === "all") {
            // Fetch from all providers concurrently
            let tmdbData = {};
            try {
                tmdbData = await fetchTmdbMetadata(tmdbId, type, season, episode);
            } catch (e) {
                console.warn("[TMDB] Metadata fetch failed:", e.message);
                try {
                    tmdbData = await fetchTmdbMetadata(tmdbId, type);
                } catch (e2) {
                    console.error("[TMDB] Total metadata failure:", e2.message);
                }
            }
            const imdbId = tmdbData.external_ids?.imdb_id || "";

            const [riveRes, webstreamerRes, showboxRes, cinemaOSRes, vidrockRes, movieboxRes, fuckitRes, challengeRes, pikashowRes, vidluxRes] = await Promise.allSettled([
                getRiveStreams(tmdbId, type, season, episode),
                getWebstreamerStreams(imdbId, type, season, episode),
                getShowboxStreams(tmdbId, type, season, episode),
                getCinemaOSStream(tmdbId, type, season, episode),
                getVidRockStreams(tmdbId, type, season, episode),
                getMovieBoxStream(tmdbId, type, season, episode),
                getFuckItStream(tmdbId, imdbId, tmdbData.title || tmdbData.name, tmdbData.release_date?.split("-")[0] || tmdbData.first_air_date?.split("-")[0], type, season, episode),
                getChallengeStreams(tmdbId, imdbId, tmdbData.title || tmdbData.name, tmdbData.release_date?.split("-")[0] || tmdbData.first_air_date?.split("-")[0], type, season, episode),
                getPikashowStreams(tmdbId, type, season, episode),
                getVidluxStreams(tmdbId, type, season, episode, tmdbData.title || tmdbData.name, tmdbData.release_date?.split("-")[0] || tmdbData.first_air_date?.split("-")[0]),
            ]);

            const streams = [];

            if (riveRes.status === "fulfilled" && Array.isArray(riveRes.value)) {
                riveRes.value.forEach(s => {
                    let sIdx = 1;
                    const name = (s.server || "").toLowerCase();
                    if (name.includes("hindicast")) sIdx = 3;
                    else if (name.includes("guru")) sIdx = 4;
                    streams.push({ ...s, sourceIndex: sIdx });
                });
            }
            if (webstreamerRes.status === "fulfilled" && Array.isArray(webstreamerRes.value)) {
                webstreamerRes.value.forEach(s => streams.push({ ...s, sourceIndex: 5 }));
            }
            if (showboxRes.status === "fulfilled" && showboxRes.value && showboxRes.value.success && Array.isArray(showboxRes.value.streams)) {
                showboxRes.value.streams.forEach(s => streams.push({ ...s, sourceIndex: 6 }));
            }
            if (cinemaOSRes.status === "fulfilled" && cinemaOSRes.value && cinemaOSRes.value.success && Array.isArray(cinemaOSRes.value.streams)) {
                cinemaOSRes.value.streams.forEach(s => streams.push({ ...s, sourceIndex: 7 }));
            }
            if (vidrockRes.status === "fulfilled" && Array.isArray(vidrockRes.value)) {
                vidrockRes.value.forEach(s => streams.push({ ...s, sourceIndex: 8 }));
            }
            if (movieboxRes.status === "fulfilled" && movieboxRes.value && movieboxRes.value.success && Array.isArray(movieboxRes.value.streams)) {
                movieboxRes.value.streams.forEach(s => streams.push({ ...s, sourceIndex: 2 }));
            }
            if (fuckitRes.status === "fulfilled" && fuckitRes.value && fuckitRes.value.success && Array.isArray(fuckitRes.value.streams)) {
                fuckitRes.value.streams.forEach(s => streams.push({ ...s, sourceIndex: 9 }));
            }
            if (challengeRes.status === "fulfilled" && challengeRes.value && challengeRes.value.success && Array.isArray(challengeRes.value.streams)) {
                challengeRes.value.streams.forEach(s => streams.push({ ...s, sourceIndex: 10 }));
            }
            if (pikashowRes.status === "fulfilled" && pikashowRes.value && pikashowRes.value.success && Array.isArray(pikashowRes.value.streams)) {
                pikashowRes.value.streams.forEach(s => streams.push({ ...s, sourceIndex: 11 }));
            }
            if (vidluxRes.status === "fulfilled" && vidluxRes.value && vidluxRes.value.success && Array.isArray(vidluxRes.value.streams)) {
                vidluxRes.value.streams.forEach(s => streams.push({ ...s, sourceIndex: 12 }));
            }


            const formatStream = (s, fallbackMetadata) => {
                let url = s.url || s.stream_url || null;
                const metadata = s.server || s.name || s.source || fallbackMetadata || "Unknown";
                let referer = null;
                let origin = null;



                if (s.headers) {
                    if (!referer) referer = s.headers.referer || s.headers.Referer || null;
                    if (!origin) origin = s.headers.origin || s.headers.Origin || null;
                }
                if (s.behaviorHints?.proxyHeaders?.request) {
                    const req = s.behaviorHints.proxyHeaders.request;
                    if (!referer) referer = req.referer || req.Referer || null;
                    if (!origin) origin = req.origin || req.Origin || null;
                }
                return {
                    url,
                    metadata,
                    referer,
                    origin,
                    quality: s.quality || null,
                    type: s.type || s.format || (url && url.includes(".m3u8") ? "m3u8" : "mp4") || null,
                    lang: s.language || s.lang || null
                };
            };
            
            responseData = streams.map((s, sIdx) => {
                const formatted = formatStream(s, "Unknown");
                formatted.metadata = `Server ${s.sourceIndex}`;
                if (s.sourceIndex === 6) {
                    delete formatted.lang;
                    formatted.origin = formatted.referer;
                }
                return formatted;
            });
        } else {
            const idx = parseInt(index);
            let streamsArray = [];

            if (idx === 1 || idx === 3 || idx === 4) {
                const server = RIVE_SERVERS[idx - 1];
                let data = await getRiveRawResponse(tmdbId, type, server, season, episode);
                if (data?.data?.sources) {
                    data.data.sources.forEach(source => {
                        let url = source?.url || null;
                        let referer = "https://www.rivestream.app";
                        let origin = null;



                        streamsArray.push({
                            url: url,
                            metadata: source?.source || server || null,
                            referer: referer,
                            origin: origin,
                            quality: source?.quality || null,
                            type: source?.format === "hls" ? "m3u8" : (source?.type || "mp4")
                        });
                    });
                }
            } else if (idx === 2) {
                const r = await getMovieBoxStream(tmdbId, type, season, episode);
                if (r.success) {
                    streamsArray = r.streams;
                } else {
                    console.error(`[Error] Source 2 failed: ${r.error}`);
                    // Fallback to empty but don't crash
                    streamsArray = [];
                }
            } else if (idx === 5) {
                const tmdbData = await fetchTmdbMetadata(tmdbId, type);
                const imdbId = tmdbData.external_ids?.imdb_id || "";
                streamsArray = await getWebstreamerStreams(imdbId, type, season, episode);
            } else if (idx === 6) {
                const r = await getShowboxStreams(tmdbId, type, season, episode);
                if (r?.success && Array.isArray(r.streams)) streamsArray = r.streams;
            } else if (idx === 7) {
                const r = await getCinemaOSStream(tmdbId, type, season, episode);
                if (r?.success) streamsArray = r.streams;
            } else if (idx === 8) {
                streamsArray = await getVidRockStreams(tmdbId, type, season, episode);
            } else if (idx === 9) {
                const tmdbData = await fetchTmdbMetadata(tmdbId, type, season, episode);
                const imdbId = tmdbData.external_ids?.imdb_id || "";
                const title = tmdbData.title || tmdbData.name || "";
                const releaseYear = (tmdbData.release_date || tmdbData.first_air_date || "").split("-")[0];
                const r = await getFuckItStream(tmdbId, imdbId, title, releaseYear, type, season, episode);
                if (r?.success) streamsArray = r.streams;
            } else if (idx === 10) {
                const tmdbData = await fetchTmdbMetadata(tmdbId, type, season, episode);
                const imdbId = tmdbData.external_ids?.imdb_id || "";
                const title = tmdbData.title || tmdbData.name || "";
                const releaseYear = (tmdbData.release_date || tmdbData.first_air_date || "").split("-")[0];
                const r = await getChallengeRawResponse(tmdbId, imdbId, title, releaseYear, type, season, episode);
                if (r?.success) streamsArray = r.streams || r.data || [];
            } else if (idx === 11) {
                const r = await getPikashowStreams(tmdbId, type, season, episode);
                if (r?.success) streamsArray = r.streams;
            } else if (idx === 12) {
                const tmdbData = await fetchTmdbMetadata(tmdbId, type, season, episode);
                const title = tmdbData.title || tmdbData.name || "";
                const releaseYear = (tmdbData.release_date || tmdbData.first_air_date || "").split("-")[0];
                const r = await getVidluxStreams(tmdbId, type, season, episode, title, releaseYear);
                if (r?.success) streamsArray = r.streams;
            } else {
                const sourceNames = {
                    1: "Flowcast (Rive)",
                    2: "MovieBox",
                    3: "Hindicast (Rive)", 
                    4: "Guru (Rive)",
                    5: "Webstreamer",
                    6: "Showbox",
                    7: "CinemaOS (V3)",
                    8: "VidRock",
                    9: "FuckIt",
                    10: "Challenge Server",
                    11: "Pikashow",
                    12: "Vidlux"
                };
                return res.status(404).json({ 
                    error: `Invalid index: ${index}`, 
                    message: "Index must be between 1-12 or 'all'",
                    availableSources: sourceNames 
                });
            }

             const formatStream = (s, fallbackMetadata) => {
                let url = s.url || s.stream_url || null;
                const metadata = s.server || s.name || s.source || fallbackMetadata || "Unknown";
                let referer = null;
                let origin = null;



                if (s.headers) {
                    if (!referer) referer = s.headers.referer || s.headers.Referer || null;
                    if (!origin) origin = s.headers.origin || s.headers.Origin || null;
                }
                if (s.behaviorHints?.proxyHeaders?.request) {
                    const req = s.behaviorHints.proxyHeaders.request;
                    if (!referer) referer = req.referer || req.Referer || null;
                    if (!origin) origin = req.origin || req.Origin || null;
                }
                return {
                    url,
                    metadata,
                    referer,
                    origin,
                    quality: s.quality || null,
                    type: s.type || s.format || (url && url.includes(".m3u8") ? "m3u8" : "mp4") || null,
                    lang: s.language || s.lang || null
                };
            };

            // Avoid double formatting if it's already manually pushed like in Rive
            if (idx === 1 || idx === 3 || idx === 4) {
               responseData = streamsArray.map((s) => {
                   return {
                       url: s.url,
                       metadata: `Server ${idx}`,
                       referer: s.referer,
                       origin: s.origin,
                       quality: s.quality || null,
                       type: s.type || null
                   };
               }); 
            } else {
                responseData = streamsArray.map((s) => {
                    const formatted = formatStream(s, "Unknown");
                    formatted.metadata = `Server ${idx}`;
                    if (idx === 6) {
                        delete formatted.lang;
                        formatted.origin = formatted.referer;
                    }
                    return formatted;
                });
            }
        }

        if (responseData) {
            // streamCache.set(streamCacheKey, responseData);
            return res.json(responseData);
        }
    } catch (error) {
        console.error("API Error:", error);
        res.status(500).json({ error: error.message });
    }
});

app.get("/api/download/:type", async (req, res) => {
    const { type } = req.params;
    const { id: tmdbId, season = "", episode = "" } = req.query;

    if (!tmdbId) {
        return res.status(400).json({ error: "Missing tmdbId (id) query parameter" });
    }

    try {
        console.log(`[Download API] Request for ${type} ID: ${tmdbId} (S:${season}E:${episode})`);
        
        // Step 1: Fetch TMDB Metadata for imdb_id and title
        const tmdbData = await fetchTmdbMetadata(tmdbId, type, season, episode);
        const imdbId = tmdbData.external_ids?.imdb_id || "";
        const title = tmdbData.title || tmdbData.name || "Unknown";
        const year = (tmdbData.release_date || tmdbData.first_air_date || "").split("-")[0];

        // Step 2: Fetch streams from ALL available providers
        const [
            riveRes, 
            source5Res, 
            showboxRes, 
            source7Res, 
            vidrockRes, 
            movieboxRes, 
            fuckitRes,
            challengeRes,
            pikashowRes
        ] = await Promise.allSettled([
            getRiveStreams(tmdbId, type, season, episode),
            getWebstreamerStreams(imdbId, type, season, episode),
            getShowboxStreams(tmdbId, type, season, episode),
            getCinemaOSStream(tmdbId, type, season, episode),
            getVidRockStreams(tmdbId, type, season, episode),
            getMovieBoxStream(tmdbId, type, season, episode),
            getFuckItStream(tmdbId, imdbId, title, year, type, season, episode),
            getChallengeStreams(tmdbId, imdbId, title, year, type, season, episode),
            getPikashowStreams(tmdbId, type, season, episode),
            getVidluxStreams(tmdbId, type, season, episode, title, year)
        ]);

        let allStreams = [];
        
        const processResult = (res, sourceIndex) => {
            if (res.status === "fulfilled") {
                const val = res.value;
                if (Array.isArray(val)) {
                    allStreams.push(...val.map(s => ({ ...s, sourceIndex })));
                } else if (val && val.success && Array.isArray(val.streams)) {
                    allStreams.push(...val.streams.map(s => ({ ...s, sourceIndex })));
                } else if (val && val.success && val.data) {
                    allStreams.push({ ...val.data, sourceIndex });
                }
            }
        };

        processResult(riveRes, 1);
        processResult(source5Res, 5);
        processResult(showboxRes, 6);
        processResult(source7Res, 7);
        processResult(vidrockRes, 8);
        processResult(movieboxRes, 2);
        processResult(fuckitRes, 9);
        processResult(challengeRes, 10);
        processResult(pikashowRes, 11);
        processResult(vidluxRes, 12);

        // Adjust Rive sub-source indices based on server name
        allStreams.forEach(s => {
            if (s.sourceIndex === 1) {
                const name = (s.server || "").toLowerCase();
                if (name.includes("hindicast")) s.sourceIndex = 3;
                else if (name.includes("guru")) s.sourceIndex = 4;
            }
        });

        if (allStreams.length === 0) {
            return res.json([]);
        }

        // Standardize format and filter out obvious HLS before validation
        const formatStream = (s) => {
            let url = s.url || s.stream_url || null;
            if (!url) return null;

            const metadata = s.server || s.name || s.source || "Unknown";
            let referer = null;
            let origin = null;
            


            if (s.headers) {
                if (!referer) referer = s.headers.referer || s.headers.Referer || null;
                if (!origin) origin = s.headers.origin || s.headers.Origin || null;
            }
            if (s.behaviorHints?.proxyHeaders?.request) {
                const reqHeaders = s.behaviorHints.proxyHeaders.request;
                if (!referer) referer = reqHeaders.referer || reqHeaders.Referer || null;
                if (!origin) origin = reqHeaders.origin || reqHeaders.Origin || null;
            }

            // Determine if it's HLS
            const isHLS = (url && (url.includes(".m3u8") || url.includes(".m3u") || url.includes("/playlist"))) || 
                         (s.type === "m3u8" || s.format === "m3u8" || s.format === "hls") || (s.isHls);

            if (isHLS) return null;

            return {
                url,
                metadata,
                referer,
                origin,
                quality: s.quality || null,
                type: (url.includes(".mkv") ? "mkv" : "mp4"),
                sourceIndex: s.sourceIndex
            };
        };

        const rawFormattedStreams = allStreams.map(formatStream).filter(s => s !== null);
        const formattedStreams = rawFormattedStreams.map((s) => {
            s.metadata = `Server ${s.sourceIndex}`;
            delete s.sourceIndex;
            return s;
        });

        // Step 3: Validate URLs concurrently
        console.log(`[Validator] Validating ${formattedStreams.length} URLs...`);
        
        const validationResults = await Promise.all(
            formattedStreams.map(async (s) => {
                const { isValid, contentType, size } = await validateUrl(s);
                
                if (!isValid) return null;

                // Exclusion: HLS Content-Types
                const isHLS = contentType.includes("mpegurl") || contentType.includes("m3u8") || contentType.includes("video/hls");
                
                // Inclusion: downloadable Content-Types
                const isDownloadable = contentType.includes("video/") || contentType.includes("application/octet-stream") || contentType.includes("application/x-matroska");

                if (isHLS) {
                    return null;
                }

                // Format size string
                const sizeStr = size > 0 ? (size / (1024 * 1024 * 1024)).toFixed(2) + " GB" : "Unknown Size";

                if (isDownloadable || contentType === "") {
                     return { 
                        ...s, 
                        size: size > 0 ? size : null,
                        sizeText: sizeStr,
                        contentType 
                    };
                }

                return null;
            })
        );

        const validStreams = validationResults.filter(s => s !== null);
        console.log(`[Validator] Found ${validStreams.length} valid downloadable streams out of ${formattedStreams.length}`);

        return res.json(validStreams);

    } catch (error) {
        console.error("Download API Error:", error);
        res.status(500).json({ error: error.message });
    }
});

// --- AnimeSalt Endpoints ---
app.get('/api/anime/home', async (req, res) => {
    try {
        const data = await animeProvider.getHome();
        res.json({ success: true, data });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
});

app.get('/api/anime/search', async (req, res) => {
    const s = req.query.s || req.query.q || '';
    const page = parseInt(req.query.page) || 1;
    if (!s) return res.status(400).json({ success: false, error: 'Search query is required' });
    try {
        const results = await animeProvider.searchAnime(s, page);
        res.json({ success: true, query: s, page, results });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
});

app.get('/api/anime/details/movie/:slug', async (req, res) => {
    try {
        const data = await animeProvider.getMovieDetails(req.params.slug);
        res.json({ success: true, data });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
});

app.get('/api/anime/details/series/:slug', async (req, res) => {
    try {
        const data = await animeProvider.getSeriesDetails(req.params.slug);
        res.json({ success: true, data });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
});

app.get('/api/anime/details/episode/:slug', async (req, res) => {
    try {
        const data = await animeProvider.getEpisodeDetails(req.params.slug);
        res.json({ success: true, data });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
});

app.get("/health", (req, res) => {
    res.status(200).send("OK");
});

app.get("/api/games", async (req, res) => {
    try {
        const response = await axios.get("https://raw.githubusercontent.com/Veltrixcoder/youtube-playables/refs/heads/main/games.json");
        res.json(response.data);
    } catch (error) {
        console.error("Games fetch error:", error.message);
        res.status(500).json({ error: "Failed to fetch games" });
    }
});

app.get("/api/tmdb/*", async (req, res) => {
    const path = req.params[0];
    
    // Choose key based on query index or rotate
    const keyIndex = parseInt(req.query.ki) || 0;
    const apiKey = TMDB_KEYS[keyIndex % TMDB_KEYS.length];

    if (!apiKey) {
        return res.status(400).json({ error: "No API key available" });
    }

    const tmdbUrl = `https://api.themoviedb.org/3/${path}`;
    const params = { ...req.query };
    delete params.apikey;
    delete params.api_key;
    delete params.ki; // Remove key index from final query
    params.api_key = apiKey;

    try {
        const response = await axios.get(tmdbUrl, { params });
        res.json(response.data);
    } catch (error) {
        console.error("TMDB Proxy Error:", error.message);
        res.status(error.response?.status || 500).json(error.response?.data || { error: error.message });
    }
});

// Use the first key for internal fetches
const DEFAULT_TMDB_KEY = TMDB_KEYS[0];

async function fetchTmdbMetadata(tmdbId, type, season = "", episode = "") {
    const isTV = type === "series" || type === "tv";
    const mediaType = isTV ? "tv" : "movie";
    
    let apiUrl = `https://api.themoviedb.org/3/${mediaType}/${tmdbId}?append_to_response=external_ids&api_key=${DEFAULT_TMDB_KEY}`;

    if (isTV && season && episode) {
        apiUrl = `https://api.themoviedb.org/3/tv/${tmdbId}/season/${season}/episode/${episode}?append_to_response=external_ids&api_key=${DEFAULT_TMDB_KEY}`;
    }

    console.log(`[TMDB] Fetching metadata: ${apiUrl}`);
    try {
        const response = await axios.get(apiUrl, {
            headers: { "accept": "application/json" },
            timeout: 10000
        });
        return response.data;
    } catch (error) {
        throw new Error(`Failed to fetch TMDB metadata: ${error.message}`);
    }
}



(async () => {
    try {
        console.log("[Server] Initializing TLS client...");
        await initTLS();
        console.log("[Server] TLS client initialized.");
    } catch (e) {
        console.error("[Server Error] TLS client init failed:", e.message);
    }
    server.listen(port, () => {
        console.log(`TMDB Stream API running at http://localhost:${port}`);
    });
})();

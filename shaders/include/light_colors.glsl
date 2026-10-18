#ifndef HEARTHLIGHT_LIGHT_COLORS
#define HEARTHLIGHT_LIGHT_COLORS

// Colour table for emitters. Index = material mask - 32, i.e. the ID assigned in
// block.properties minus 10000 minus 32. Keep block.properties and this table
// in sync; there are exactly 48 slots (IDs 10032 through 10079).
const vec3 EMITTER_COLORS[48] = vec3[48](
    vec3(0.62, 0.90, 1.00), // 10032 sea lantern
    vec3(0.95, 0.92, 1.00), // 10033 end rod
    vec3(0.62, 1.00, 0.66), // 10034 glow lichen, firefly bush
    vec3(1.00, 0.82, 0.48), // 10035 glowstone, lantern, redstone lamp
    vec3(1.00, 0.66, 0.32), // 10036 torch, campfire, furnaces
    vec3(1.00, 0.74, 0.34), // 10037 glow berries, cave vines
    vec3(1.00, 0.52, 0.16), // 10038 jack o'lantern, lit pumpkin
    vec3(1.00, 0.42, 0.10), // 10039 lava, magma
    vec3(1.00, 0.50, 0.16), // 10040 fire, shroomlight
    vec3(0.62, 0.44, 1.00), // 10041 brewing stand, enchanting table
    vec3(0.90, 0.94, 1.00), // 10042 beacon
    vec3(0.10, 0.92, 1.00), // 10043 sculk sensors, calibrated sensor
    vec3(0.14, 0.62, 0.66), // 10044 sculk, shrieker, catalyst
    vec3(0.76, 0.24, 1.00), // 10045 monster spawner, crying obsidian
    vec3(0.42, 1.00, 0.82), // 10046 sea pickle
    vec3(1.00, 0.56, 0.22), // 10047 candles, candle cakes
    vec3(1.00, 0.90, 0.52), // 10048 ochre froglight
    vec3(0.62, 1.00, 0.62), // 10049 verdant froglight
    vec3(1.00, 0.52, 0.92), // 10050 pearlescent froglight
    vec3(0.72, 0.42, 1.00), // 10051 amethyst cluster
    vec3(0.22, 0.86, 1.00), // 10052 soul fire, soul torch, soul lantern
    vec3(0.34, 0.62, 1.00), // 10053 end portal, end gateway
    vec3(0.72, 0.24, 1.00), // 10054 nether portal
    vec3(0.48, 1.00, 0.36), // 10055 copper torch, copper lantern
    vec3(1.00, 0.76, 0.38), // 10056 lit copper bulb
    vec3(0.92, 0.72, 1.00), // 10057 open eyeblossom
    vec3(0.62, 0.94, 1.00), // 10058 glow squid ambient / light block
    vec3(1.00, 0.42, 0.30), // 10059 decorated pot fire? spare warm slot
    vec3(0.80, 0.96, 1.00), // 10060 lantern-like modded
    vec3(0.95, 0.92, 1.00), // 10061 spare
    vec3(1.00, 0.66, 0.32), // 10062 spare
    vec3(1.00, 0.82, 0.48), // 10063 spare
    vec3(1.00, 1.00, 1.00), // 10064 spare
    vec3(1.00, 1.00, 1.00), // 10065 spare
    vec3(1.00, 1.00, 1.00), // 10066 spare
    vec3(1.00, 1.00, 1.00), // 10067 spare
    vec3(1.00, 1.00, 1.00), // 10068 spare
    vec3(1.00, 1.00, 1.00), // 10069 spare
    vec3(1.00, 1.00, 1.00), // 10070 spare
    vec3(1.00, 1.00, 1.00), // 10071 spare
    vec3(1.00, 1.00, 1.00), // 10072 spare
    vec3(1.00, 1.00, 1.00), // 10073 spare
    vec3(1.00, 1.00, 1.00), // 10074 spare
    vec3(1.00, 1.00, 1.00), // 10075 spare
    vec3(1.00, 1.00, 1.00), // 10076 spare
    vec3(1.00, 1.00, 1.00), // 10077 spare
    vec3(1.00, 1.00, 1.00), // 10078 spare
    vec3(1.00, 1.00, 1.00)  // 10079 spare
);

// Emitter colours are indexed by the material mask, which is the block ID from
// block.properties minus 10000. Only 32..79 are emitters.
vec3 emitter_color(int mask) {
    int index = clamp(mask, 32, 79) - 32;
    return EMITTER_COLORS[index];
}

bool is_emitter_mask(int mask) { return mask >= 32 && mask < 80; }

// Light colours for held items. item.properties assigns 10032+ to the items
// that emit light; the table below is deliberately small because the held light
// only needs a warm/blue/green distinction.
vec3 held_item_color(int item_id) {
    if (item_id >= 32 && item_id < 48) {
        return EMITTER_COLORS[item_id - 32];
    }
    return vec3(1.0);
}

#endif

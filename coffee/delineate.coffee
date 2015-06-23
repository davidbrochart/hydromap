L.mapbox.accessToken = 'pk.eyJ1IjoiZGF2aWRicm9jaGFydCIsImEiOiJ6eU40bEVvIn0.xnMppw5d4NoZK_11lA-lGw'
map = L.mapbox.map('map', 'examples.map-2k9d7u0c').setView([-10, -60], 5)
pix_deg = 0.0083333333333
pix_deg2 = (pix_deg + pix_deg * 1e-5) / 2
tiles = 0
x_deg = 0
y_deg = 0
x = 0
y = 0
outlet = 0
neighbors_memsize = 1024
neighbors_i = 0
neighbors = new Uint8Array(neighbors_memsize)
tile_width = 1200
url = 0
polygons = 0
polyLayers = 0
pix_i = 0
pack_size = 100

wait = (ms) ->
    deferred = Q.defer()
    setTimeout( ->
        deferred.resolve()
    , ms)
    return deferred.promise

addPixel = ->
    polygons[pix_i % pack_size] = turf.polygon([[
        [x_deg - pix_deg2, y_deg - pix_deg2],
        [x_deg - pix_deg2, y_deg + pix_deg2],
        [x_deg + pix_deg2, y_deg + pix_deg2],
        [x_deg + pix_deg2, y_deg - pix_deg2],
        [x_deg - pix_deg2, y_deg - pix_deg2]
    ]])
    done_packing = false
    pix_i += 1
    i = pix_i
    level = 1
    while !done_packing
        if i % pack_size == 0
            polygons[level * pack_size + (i / pack_size - 1) % pack_size] = turf.merge(turf.featurecollection(polygons[(level * pack_size - pack_size)..(level * pack_size - 1)]))
            polygons[level * pack_size + (i / pack_size - 1) % pack_size].properties = {
                "fill": "#6BC65F",
                "stroke": "#6BC65F",
                "stroke-width": 1
            }
            polyLayers[level * pack_size + (i / pack_size - 1) % pack_size - pack_size] = L.mapbox.featureLayer(polygons[level * pack_size + (i / pack_size - 1) % pack_size]).addTo(map)
            #console.log 'Added polygon at ' + (level * pack_size + (i / pack_size - 1) % pack_size - pack_size) + ', level = ' + level
            for k in [(level * pack_size - pack_size)..(level * pack_size - 1)]
                polygons[k] = 0
                if level > 1
                    if polyLayers[k - pack_size]?
                        #console.log 'Removed polygon at ' + (k - pack_size) + ', level = ' + level
                        map.removeLayer(polyLayers[k - pack_size])
            i /= pack_size
            level += 1
        else
            done_packing = true

getTile = (url) ->
    console.log 'Downloading ' + url
    deferred = Q.defer()
    req = new XMLHttpRequest()
    req.open 'GET', url, true
    req.responseType = 'arraybuffer'
    req.onload = ->
        arrayBuffer = req.response
        if arrayBuffer
            console.log 'Done!'
            deferred.resolve(new Uint8Array(arrayBuffer))
        else
            deferred.reject(new Error("Can't do it"))
    req.send(null)
    return deferred.promise

processTile = ->
    done = false
    skip = false
    pix_i = 0
    polygons = []
    polyLayers = []
    while !done
        if !skip
            addPixel()
            if pix_i % pack_size == 0
                yield wait(1)
        skip = false
        nb = neighbors[neighbors_i]
        if nb == 255
            nb = 0
            for i in [0..7]
                if i < 4
                    dir_back = 1 << (i + 4)
                else
                    dir_back = 1 << (i - 4)
                dir_next = go_get_dir(1 << i, false)
                if dir_next == -1
                    dir_next = yield Q.async(load_tile_and_go_get_dir)(1 << i, false)
                if dir_next == dir_back
                    nb = nb | (1 << i)
            neighbors[neighbors_i] = nb
        if nb == 0
            if neighbors_i == 0
                done = true
            else
                addPixel()
                if pix_i % pack_size == 0
                    yield wait(1)
                go_down = true
                while go_down
                    if go_get_dir(tiles[0][y * tile_width + x], true) == -1
                        yield Q.async(load_tile_and_go_get_dir)(tiles[0][y * tile_width + x], true)
                    neighbors_i -= 1
                    nb = neighbors[neighbors_i]
                    i = find1(nb)
                    nb = nb & (255 - (1 << i))
                    if nb == 0
                        if neighbors_i == 0
                            go_down = false
                            done = true
                    else
                        go_down = false
                        skip = true
                    neighbors[neighbors_i] = nb
        else
            neighbors_i += 1
            if neighbors_i == neighbors_memsize
                neighbors_new = new Uint8Array(neighbors_memsize * 2)
                for i in [0..(neighbors_memsize - 1)]
                    neighbors_new[i] = neighbors[i]
                neighbors = neighbors_new
                neighbors_memsize *= 2
            neighbors[neighbors_i] = 255
            i = find1(nb)
            if go_get_dir(1 << i, true) == -1
                yield Q.async(load_tile_and_go_get_dir)(1 << i, true)
        if done
            for layer in polyLayers
                map.removeLayer(layer)
            watershed = turf.merge(turf.featurecollection(polygons))
            watershed.properties = {
                "fill": "#6BC65F",
                "stroke": "#6BC65F",
                "stroke-width": 1
            }
            watershedLayer = L.mapbox.featureLayer(watershed).addTo(map)
            outletLayer = L.mapbox.featureLayer(outlet).addTo(map)
            outletLayer.bindPopup('<strong>Area</strong> = ' + round(turf.area(watershed) / 1e6, 1).toString() + ' km²').addTo(map)
            watershedLayer.on('mouseover', (e) -> outletLayer.openPopup())
            watershedLayer.on('click', (e) ->
                url = 'data:text/json;charset=utf8,' + encodeURIComponent(JSON.stringify(watershed.geometry))
                link = document.createElement('a')
                link.href = url
                link.download = 'watershed.json'
                link.click()
                alert('Watershed GeoJSON downloaded')
            )

find1 = (a) ->
    i = 0
    while (a & 1) == 0
        a = a >> 1
        i += 1
    return i

go_get_dir = (dir, go) ->
    x_next = x
    y_next = y
    x_deg_next = x_deg
    y_deg_next = y_deg
    if dir == 1
        x_next += 1
    else if dir == 2
        x_next += 1
        y_next += 1
    else if dir == 4
        y_next += 1
    else if dir == 8
        x_next -= 1
        y_next += 1
    else if dir == 16
        x_next -= 1
    else if dir == 32
        x_next -= 1
        y_next -= 1
    else if dir == 64
        y_next -= 1
    else if dir == 128
        x_next += 1
        y_next -= 1
    x_deg_next += (x_next - x) * pix_deg
    y_deg_next -= (y_next - y) * pix_deg
    if x_next == -1 or y_next == -1 or x_next == tile_width or y_next == tile_width
        return -1
    else
        if go
            x = x_next
            y = y_next
            x_deg = x_deg_next
            y_deg = y_deg_next
        return tiles[0][y_next * tile_width + x_next]

load_tile_and_go_get_dir = (dir, go) ->
    x_next = x
    y_next = y
    x_deg_next = x_deg
    y_deg_next = y_deg
    tile_i = 0
    if dir == 1
        x_next += 1
    else if dir == 2
        x_next += 1
        y_next += 1
    else if dir == 4
        y_next += 1
    else if dir == 8
        x_next -= 1
        y_next += 1
    else if dir == 16
        x_next -= 1
    else if dir == 32
        x_next -= 1
        y_next -= 1
    else if dir == 64
        y_next -= 1
    else if dir == 128
        x_next += 1
        y_next -= 1
    x_deg_next += (x_next - x) * pix_deg
    y_deg_next -= (y_next - y) * pix_deg
    if x_next == -1 and y_next == -1
        x_next = tile_width - 1
        y_next = tile_width - 1
        if go
            tiles[1] = tiles[7]
            tiles[2] = tiles[0]
            tiles[3] = tiles[5]
            tiles[0] = tiles[6]
            if tiles[0] == 0
                tiles[0] = yield getTile(get_url(y_deg_next, x_deg_next, false))
            tiles[4] = 0
            tiles[5] = 0
            tiles[6] = 0
            tiles[7] = 0
            tiles[8] = 0
        else
            tile_i = 6
            if tiles[tile_i] == 0
                tiles[tile_i] = yield getTile(get_url(y_deg_next, x_deg_next, false))
    else if x_next == tile_width and y_next == -1
        x_next = 0
        y_next = tile_width - 1
        if go
            tiles[3] = tiles[1]
            tiles[4] = tiles[0]
            tiles[5] = tiles[7]
            tiles[0] = tiles[8]
            if tiles[0] == 0
                tiles[0] = yield getTile(get_url(y_deg_next, x_deg_next, false))
            tiles[2] = 0
            tiles[1] = 0
            tiles[8] = 0
            tiles[7] = 0
            tiles[6] = 0
        else
            tile_i = 8
            if tiles[tile_i] == 0
                tiles[tile_i] = yield getTile(get_url(y_deg_next, x_deg_next, false))
    else if x_next == tile_width and y_next == tile_width
        x_next = 0
        y_next = 0
        if go
            tiles[5] = tiles[3]
            tiles[6] = tiles[0]
            tiles[7] = tiles[1]
            tiles[0] = tiles[2]
            if tiles[0] == 0
                tiles[0] = yield getTile(get_url(y_deg_next, x_deg_next, false))
            tiles[4] = 0
            tiles[3] = 0
            tiles[2] = 0
            tiles[1] = 0
            tiles[8] = 0
        else
            tile_i = 2
            if tiles[tile_i] == 0
                tiles[tile_i] = yield getTile(get_url(y_deg_next, x_deg_next, false))
    else if x_next == -1 and y_next == tile_width
        x_next = tile_width - 1
        y_next = 0
        if go
            tiles[7] = tiles[5]
            tiles[8] = tiles[0]
            tiles[1] = tiles[3]
            tiles[0] = tiles[4]
            if tiles[0] == 0
                tiles[0] = yield getTile(get_url(y_deg_next, x_deg_next, false))
            tiles[6] = 0
            tiles[5] = 0
            tiles[4] = 0
            tiles[3] = 0
            tiles[2] = 0
        else
            tile_i = 4
            if tiles[tile_i] == 0
                tiles[tile_i] = yield getTile(get_url(y_deg_next, x_deg_next, false))
    else if y_next == -1
        y_next = tile_width - 1
        if go
            tiles[4] = tiles[5]
            tiles[3] = tiles[0]
            tiles[2] = tiles[1]
            tiles[5] = tiles[6]
            tiles[0] = tiles[7]
            tiles[1] = tiles[8]
            if tiles[0] == 0
                tiles[0] = yield getTile(get_url(y_deg_next, x_deg_next, false))
            tiles[6] = 0
            tiles[7] = 0
            tiles[8] = 0
        else
            tile_i = 7
            if tiles[tile_i] == 0
                tiles[tile_i] = yield getTile(get_url(y_deg_next, x_deg_next, false))
    else if x_next == tile_width
        x_next = 0
        if go
            tiles[6] = tiles[7]
            tiles[5] = tiles[0]
            tiles[4] = tiles[3]
            tiles[7] = tiles[8]
            tiles[0] = tiles[1]
            tiles[3] = tiles[2]
            if tiles[0] == 0
                tiles[0] = yield getTile(get_url(y_deg_next, x_deg_next, false))
            tiles[8] = 0
            tiles[1] = 0
            tiles[2] = 0
        else
            tile_i = 1
            if tiles[tile_i] == 0
                tiles[tile_i] = yield getTile(get_url(y_deg_next, x_deg_next, false))
    else if y_next == tile_width
        y_next = 0
        if go
            tiles[6] = tiles[5]
            tiles[7] = tiles[0]
            tiles[8] = tiles[1]
            tiles[5] = tiles[4]
            tiles[0] = tiles[3]
            tiles[1] = tiles[2]
            if tiles[0] == 0
                tiles[0] = yield getTile(get_url(y_deg_next, x_deg_next, false))
            tiles[4] = 0
            tiles[3] = 0
            tiles[2] = 0
        else
            tile_i = 3
            if tiles[tile_i] == 0
                tiles[tile_i] = yield getTile(get_url(y_deg_next, x_deg_next, false))
    else if x_next == -1
        x_next = tile_width - 1
        if go
            tiles[8] = tiles[7]
            tiles[1] = tiles[0]
            tiles[2] = tiles[3]
            tiles[7] = tiles[6]
            tiles[0] = tiles[5]
            tiles[3] = tiles[4]
            if tiles[0] == 0
                tiles[0] = yield getTile(get_url(y_deg_next, x_deg_next, false))
            tiles[6] = 0
            tiles[5] = 0
            tiles[4] = 0
        else
            tile_i = 5
            if tiles[tile_i] == 0
                tiles[tile_i] = yield getTile(get_url(y_deg_next, x_deg_next, false))
    if go
        x = x_next
        y = y_next
        x_deg = x_deg_next
        y_deg = y_deg_next
    return tiles[tile_i][y_next * tile_width + x_next]

map_on_click = (evt) ->
    url = get_url(evt.latlng.lat, evt.latlng.lng, true)
    outlet = turf.point([x_deg, y_deg])
    neighbors_i = 0
    neighbors[0] = 255
    tiles = [0, 0, 0, 0, 0, 0, 0, 0, 0]
    Q.spawn(run)

run = ->
    tiles[0] = yield getTile(url)
    Q.async(processTile)()

map.on('click', map_on_click)

round = (number, precision) ->
    mult = Math.pow(10, precision)
    return Math.round(number * mult) / mult

get_url = (lat, lon, set_xy) ->
    lat = round(lat, 5)
    lon = round(lon, 5)
    ret = {}
    lat0 = 90
    lon0 = -180
    lat_str
    lon_str
    tile_name
    tile_code = {
        '40N_80W': 'njt5o2dpcx9lzig',
        '20N_30E': 'ls8f3pyhl7f3ysq',
        '70N_160E': 'rcdlrof5vnpq4u8',
        '40S_110E': 'pli2vv4tu7zg0vc',
        '10S_60W': 'vz169b4rb0dpokv',
        '10N_180E': '7cm7k4ns9efdyyj',
        '0N_0E': 'q3c4m9jlfpxqc63',
        '50N_70E': 'd9ihizwythu4mki',
        '50N_130W': '9l3gynlr804gw6k',
        '10S_60E': 'mxd445xbzoq68wz',
        '70N_60W': 'w4ksxwb2sxo92ia',
        '70N_90W': '643krk0ahqegh29',
        '60N_0E': 'ig9np311apxwywu',
        '40N_170E': 'a9f68i00sddb21h',
        '60N_90E': '7ppd0auquja7cha',
        '40N_60W': '6cqvbwcf4hjwbuq',
        '20S_100W': 'v0yeu59q4eopq2t',
        '0N_60W': '8h7bnwjhk36m4xq',
        '10N_140E': 'xo6kdts6wijvftn',
        '50N_100E': 'qr043ar5gaflp25',
        '40N_70W': 'fv02n108a3t471m',
        '60N_180E': 'wm7ai83hmlw0gbh',
        '50N_30E': '74bsr18q8aj5gzz',
        '10S_30E': 'bp2gai5uwkcolw2',
        '0N_50E': 'hqo12wfpq7q0ybe',
        '20N_150E': 'xpbqct99r7x1uxg',
        '10N_40E': 'kyko320y1xmzid6',
        '70N_50E': 'fjvhcu58630jg5t',
        '70N_100W': 'zm5uo7bo8so4ml4',
        '0N_80W': '4hrms9iaijj9quu',
        '50S_130E': 'x3lvela6fbjw32n',
        '30S_120E': 'pdmy538eze0j8ii',
        '20S_30E': 'us5v7ggmkb4j9jz',
        '10N_130E': 'rmm098zv13hjbcz',
        '20N_130E': '2ahcbqp11ymyyl5',
        '50N_110W': 'rqqtu2kfjbsg634',
        '30N_130W': 's2f49ctthghvnqa',
        '50N_40E': 'o4vx09kuzncbkm1',
        '40N_130E': 'cztyw8et0ofxzi8',
        '40N_180E': 'svm09gq9yz85yrm',
        '0N_170E': 'fw6prlx0d08x5o0',
        '10N_110E': '6jbc195o85tgx4l',
        '70N_70E': '469mlarc381lsom',
        '60N_80E': 'fxihjscygbq7m5v',
        '20S_20E': '1shz7rjreu3rmga',
        '20S_120E': 'vhturkmybky6or6',
        '10N_100W': 'a8e5grbrelki50k',
        '50N_0E': 'c95qdkj3t3ikt3u',
        '20N_20W': 'nuvxx950y7ko46f',
        '50N_100W': 'gjrtaneav8mc5he',
        '60N_130W': 'spwzdn8gm4406wo',
        '70N_180E': '8y8ldhxz48b50h0',
        '10S_100W': 'mdig6tpluqggw5r',
        '40N_30E': 'flmc5oftqvlcfvh',
        '20N_50W': '32j7an9zu6ppxob',
        '30N_120W': 'yz3r44lstmrbq4n',
        '20S_170E': 'raw3sdolobx5m6b',
        '30N_120E': 'webmh73x6nzykbq',
        '40S_50W': '9kcrobjb81urhf7',
        '30N_40E': 'aqswmk85xawse1x',
        '70N_150E': 'acy3j9jkybnnhfn',
        '20S_40E': 'dk9y0vb70stdbgo',
        '10S_90E': 'fzggjjsa4riaoxv',
        '20N_70E': '8o7uspbksjjjfte',
        '10N_60W': '1iu2g7qws543s77',
        '50N_180E': '86768dlqamgdhnp',
        '70N_40E': 'ebvr0x8xonc8tu9',
        '40N_90E': 'kgu11ddovji6qg0',
        '30N_60W': 'cjlju7rif77tm9p',
        '50S_140E': '0p7qhfjoezohmvg',
        '0N_150E': '59xy13gw2aftsoy',
        '20N_160E': 'r1tendiqpssbrgj',
        '30N_140E': 'gfdh6brfbu6ozr3',
        '60N_110W': '27glhbgxcvjdsj3',
        '40N_40E': '38x1dzu1hgmuo10',
        '70N_110E': 'ilfcu0jimcuu22y',
        '30S_100W': 'he5a0jhj7b3u37m',
        '50S_40W': 'ul76r0hqufkkito',
        '20N_100E': 'zv0ftnkg6978d1n',
        '0N_10E': 'e6zwm2ve6170rnc',
        '40S_70W': 'lt520yjkzvobjs0',
        '50N_130E': 'prr63cqsy2sq6l5',
        '50S_170E': 'j66g3gmsr97hz7w',
        '40N_100W': 'seu1iym7l3yawvr',
        '60N_10E': 'conbfw17m90cr65',
        '30N_70E': 'dgl15onm7366j9y',
        '40N_110W': 'x9d0c0nusvsnvkf',
        '0N_40W': '7d62jroploskrdz',
        '10N_30E': 'ufiiimxmi9q5rsq',
        '40N_10E': 'evdq82t5hnvlgup',
        '30N_150E': 'ju0vhdvs9q32mcf',
        '30N_80W': 'azwymrifj8020k5',
        '60N_30E': '3fo08jcqwvd2hri',
        '10N_20E': 'xue5zm4fbmzmo5l',
        '30N_100W': '7d4uan2bp2fyo5t',
        '20S_50W': 'lj5qpdmycd18i9s',
        '50N_80W': 'd01j1rqigwd6r4n',
        '30N_160E': '5huu7ehl9qvm434',
        '10S_50E': 'mp0r86di46cad30',
        '50N_90W': '62cjaxm4pwon3ta',
        '30S_70W': 'vcjchqdowlocrte',
        '70N_120E': 'z9vss9nffu130ya',
        '30N_130E': 'f1jumdi52vcg5hx',
        '20S_20W': 'ach4qdtxa6cvfoe',
        '60N_100W': 'iwcq9ogntx9h9zr',
        '0N_160E': 'cpmu98nntsai0fu',
        '50N_10W': 'jhfliz911qffjch',
        '60N_70E': 'rewb9fzmlpem67g',
        '20S_80W': '6yqay3jos6sthn9',
        '50S_50W': 'tt563tgfn2iccrm',
        '10S_10E': '10b693pj08lhph4',
        '0N_130E': 'n0yo92yfvocy2ys',
        '10N_50W': 'ni2bepgw20kfivr',
        '10N_120E': 'm4dqmeh8mkq8f09',
        '40N_160E': '3dfcmd7p8xvjyk5',
        '70N_10E': '3yfx21j7nggc6vg',
        '70N_30E': '4m9zcz4eueif5if',
        '30S_50E': 'ei77gp02xpl6234',
        '70N_80W': 'xsxbixdmjhuxbom',
        '40S_170E': '5tyi2av2p794x1k',
        '10N_0E': 'ut7jw1vksl7ospe',
        '50N_90E': '2tbtweuwsgououn',
        '70N_130E': 'pxqkn9t5b1lv16o',
        '50S_100W': 'jcch94px3a3lrkv',
        '30N_170E': 'x51q62qkeogycvj',
        '30S_110E': 'ref43ht78h1mxkl',
        '60N_100E': '91v4qmizu1t5chm',
        '70N_20W': 'cqysdk36jpky7sl',
        '10S_140E': 'sc1qd7xfskk1190',
        '50S_180E': '2r7oq34nuyrbrmz',
        '50N_20W': '0a3mfbgr4b3fwkf',
        '50S_60W': 'a3fakfcx18xebqw',
        '20N_100W': 'atj10syx395lock',
        '20N_40W': 'v78c8iig9u05c2c',
        '30S_40E': '9hjqr2yikdpp8pt',
        '10S_130E': 'uudwt6x8dp9w38o',
        '40N_150E': 'icd2nb7b7o6orbg',
        '50N_10E': 'r6uogmh1fpsg5gu',
        '20N_50E': 'znznm95m5u60fk3',
        '10S_160E': 'ibj3o24opajv5gl',
        '70N_10W': '57kfww0wfmvlr9c',
        '40N_10W': '93pww6nj0vdmkwh',
        '20N_110E': 'y2ltu7r6nulfn6z',
        '10N_20W': 'baivyy025t4gca6',
        '10N_80W': 'gksccwsgv0br8kv',
        '50S_80W': 'esgszubtsdhwc0d',
        '70N_0E': 'jmq6q20u1zzqe78',
        '10N_90W': 'ms46fc02ddfggaa',
        '40N_0E': 'brm28xvjp7txu6a',
        '40N_20W': 'j6aclal8hjj43sq',
        '20N_90E': '7kj50ke3t9dg2k1',
        '10N_70W': '1ehlf63ztq9ascf',
        '30S_10W': 'l76jxgrjc9chfq8',
        '30N_30E': 'c426bked8bs1p2x',
        '70N_140E': '0arx8x4o20tuc3j',
        '30N_110W': 'r50rg4dyyzlq2rp',
        '20N_80E': 'chyvj6484m3yyzw',
        '70N_170E': 'brlsfizhofanf9h',
        '50N_160E': '1bndf15xeaz75db',
        '60N_120E': 'qxun7audymzvs2j',
        '10S_120E': '4k9oiq72iojd7tw',
        '50N_120E': '1nvf48c3i5ntgfp',
        '50S_160E': 'kzzv6vaupevo667',
        '30N_20E': 'g59ucu9csoroh6d',
        '50S_110E': '5sc9507h87n9rk2',
        '20S_140E': '81plt39owmcx29t',
        '20S_40W': 'upmd0pogjc6vmwb',
        '10N_80E': 'qnumh0vszwhwg3e',
        '60N_120W': 'ekuqu87q69r1k24',
        '70N_110W': '6gaa13v5gnb7p3k',
        '50N_150E': 'm0voo0ef0t6ik5u',
        '10N_110W': 'pysk4tlowiynzkq',
        '10S_70W': 'b1buj0ma7xzkz9g',
        '40N_140W': 'q6hg1x2eapx4nzp',
        '0N_180E': 'xeq06zwex8tgz1g',
        '20S_50E': 'ry284o47frvh75s',
        '70N_80E': 'am8y1bepl6cimzq',
        '20S_10W': 'swy8xxdhqwkwzrf',
        '40N_80E': 'sq99xh0kj2e4iiu',
        '40S_130E': 'pniyneh9o29glhk',
        '50N_170E': 'osp3iio527u8a9m',
        '10N_40W': 'dhuv56y24w8k5nj',
        '30N_60E': 'vrdv94uy3p01gu9',
        '60N_50E': 'w6dokrajdg4vlx0',
        '60N_20W': 'pnlvqfblgfaaz4k',
        '60N_140W': 'igfgzntr4930h6s',
        '40N_50E': '30w4q6cpa4njbwb',
        '20S_160E': 'xmcripl7n2gygx8',
        '30N_70W': 'zq3bwir60cxbl2y',
        '10S_50W': 'ednjxma5fiup6l0',
        '30S_10E': '8wnoefc87uiiz8f',
        '20N_60E': 'wnf5qjng14lm3z6',
        '60N_110E': 'ecqbskcnw1qvx4d',
        '60N_70W': 'hwlnvkr1qrpnzc3',
        '40N_120W': 'z4797cg79jm46sd',
        '20S_70W': 'ewdv0bntx3xq090',
        '20S_150E': 'mhha19x5mf5seb2',
        '20N_80W': '41186p3wtvnp92a',
        '0N_50W': '9888rp2gt8ul4fl',
        '70N_100E': 'ukrwe7fx8ej6rkh',
        '10S_70E': 'zjslhzj7t3k05fr',
        '30S_140E': '71cke0qt9qj6qpo',
        '0N_10W': 'mqwhdvq5fpm5dvq',
        '60N_150E': 'hz1fv9czziyt4ft',
        '50S_70W': 'm2kycfffxxfuy3n',
        '30S_60W': 'mukv3pxvbwuxmv0',
        '20N_180E': 'vluofrfqlq1tq7d',
        '30S_80W': 'cywvswzxjdu0rke',
        '20S_60W': '9j6n6fn7z21nr1x',
        '20N_120W': 'nkvf20ojt3uxfek',
        '0N_100E': 'vsurwf60amex45l',
        '20N_70W': '17bv1gg3a9o27j1',
        '50N_50E': 'o1cndow58eg4iht',
        '10S_40E': 'p6n7ppnucthj3ri',
        '50S_90W': 'd76j559itl1d94f',
        '40N_140E': 'p78aivsuyysht3s',
        '0N_110E': 'd208ls5h0kaagjr',
        '10S_180E': 'ovzi3yf799mdb7l',
        '20N_0E': 'l70nfmxvozjd7k7',
        '40N_130W': '9v5iq543yn2ns9n',
        '0N_20E': 'g5riug5jsfevtcv',
        '0N_20W': '1thdgulzf3ziwrt',
        '40S_90W': 'tiyymuz1v8z4z31',
        '40S_150E': 'j3op3bvu8m1okp5',
        '20S_110E': 'xj5a0fv2r6auchr',
        '20N_20E': '1p7asnpmqw9rq4u',
        '10S_20W': 'vv5xszaadhckg6d',
        '0N_70W': 'c3as6denh34ke5g',
        '30S_90W': 'lus6tbpitf8j9po',
        '20N_170E': '1ugbxtppm7x13vl',
        '60N_170E': 'a98i7rcqx5fvlbk',
        '30N_140W': 'klbrzjdsqub1wku',
        '30S_40W': 'lqcr3kc5v800l8c',
        '0N_90W': '0r0zd2dpg8kt3ds',
        '50S_150E': '49ilumtcabfq22g',
        '30S_0E': 'ervrbl0m3tvnpu3',
        '0N_40E': 'z6u00g9m0rdpesh',
        '30N_90E': '3rrz6jwiueeg0be',
        '70N_60E': 'mipyttald7cgs6d',
        '40N_110E': 'vbff46frv6pgkmu',
        '10N_70E': 'bfyxhbb0mejotb6',
        '30N_110E': 'mduywyb0ut5whmp',
        '10N_90E': '5e2weozv466qvq9',
        '20N_10W': 'nj0uz42z5rog76o',
        '50S_120E': 'iu81a15u7gp3nq4',
        '20S_130E': 'fs9s3xadluqlv5g',
        '30N_80E': 'fwswppy42c91zy6',
        '40S_180E': 'v6vj008uec9ja7t',
        '60N_160E': '5zpvo2b7vktti7a',
        '40S_100W': '7zg5lxozkgomo5p',
        '0N_60E': 'vqyqo67uszxkezj',
        '30S_20W': 'fud1p0ywbpmt03t',
        '10S_170E': 'nw5y90t4ntqtahj',
        '30N_90W': '9u9w2ov3cuw8ue2',
        '20N_140E': 'wbhp6xp57lbqu5b',
        '60N_130E': 'tfkokya89ywzrjf',
        '70N_130W': 'sk24ldyi0gez2y4',
        '40S_140E': '6t0ndzci1yvvzos',
        '40N_20E': '46y8e2drvpc0558',
        '20S_0E': 'km8fieuehf0ievc',
        '60N_60W': 'a607whft4tau57h',
        '10N_170E': 'v3yvprk884a4r40',
        '30S_130E': '7y6wgnf7ndwyyll',
        '30N_180E': 'hndze8kj0psdo9r',
        '0N_70E': '0aet2epmdtvnj3i',
        '30S_30E': 'x2rahasj2aewd46',
        '50N_60E': 'a3dsjcsd0fuog8n',
        '20N_60W': 'o9ufvfwny6q42do',
        '10N_10W': '6k8ral35jl00z8g',
        '40N_120E': '7jq4kyvdn87x4i5',
        '70N_20E': 'aueplubete1o2xd',
        '30N_100E': 'lfz50uivpdqb166',
        '40N_90W': 'vju0gkkfoa773o0',
        '10S_80W': '0ruc1riqnl3rzza',
        '10N_60E': 'n5ee7k9mfto1104',
        '0N_120E': 'sswv3cdzvyst3e9',
        '70N_140W': '4quswlwtvxn456c',
        '10S_80E': 'jo5p4do02ubwhbm',
        '0N_90E': 'iq7i2v764t4ha22',
        '0N_140E': 'jg6r27k9l4u32d6',
        '60N_40E': '907q33vq6a5o0fk',
        '10N_150E': 'ka1m1y1dha1z75c',
        '60N_140E': '0gid8dmrylip35b',
        '30N_0E': 'r7fe9ugsky80kz8',
        '50N_20E': '3ey731tlb7duy0m',
        '30S_50W': '1dlgwyangl2jnoe',
        '50N_140E': '528kneauqf3d1ip',
        '30S_180E': '1phrgmq8kstmabk',
        '30N_10W': '2rgou9qbqg3k3m9',
        '10S_0E': 'iyp67d9ksbx90x2',
        '0N_80E': 'sikidycmwntrrhl',
        '30S_150E': '2v7kjt4wgbu6uc4',
        '20N_10E': 'ipewhaim6kmcla1',
        '0N_100W': 'sh8m2mmxm0iznka',
        '60N_20E': '7ax1ly9l8s1brzn',
        '60N_10W': 'i81h1aerrhvppqo',
        '10S_10W': 'rf5bmnkwv4395tl',
        '50N_80E': 'axibpl1v3u6643c',
        '10N_160E': '6t399mcnovfvhhg',
        '10N_100E': 'vzznnr63l8ku0bs',
        '20N_110W': 'aq4jnu47230b7hy',
        '50N_120W': '3mqc9wub3lvt9um',
        '30N_50E': 'vaf57pswj0aqfsy',
        '40N_100E': 'h2h4mpg5oi2e54l',
        '30S_170E': 'xkx6036h76ecjx6',
        '10S_20E': 'vc7sn3ig5jheb5k',
        '40S_80W': 'vqwe0k1u9k1qm73',
        '60N_90W': '48j6ie4tr6jec12',
        '60N_80W': 'krvh5e1nw4s9i5x',
        '70N_70W': 'evb65pwb599es77',
        '50N_110E': 'hckwm8kss4s09yz',
        '10S_150E': 'xk2vrdpvffsw70f',
        '10S_100E': '69qzfyqj37bdzqo',
        '0N_30E': '8yn50z10zvxuxd8',
        '70N_90E': 'u5om8ivcg5g663u',
        '20S_180E': 'vln4eo9vjz0xpie',
        '10S_90W': 'rdwm5zsqb80xz2o',
        '50N_60W': '4iu67oqfj6112z7',
        '10S_40W': '7hcb9keu1g2zij2',
        '40S_60W': 'qgef1cr6lx7dnmd',
        '20N_40E': '45pfkm2wq0xbzdt',
        '20N_120E': 're9vszajn3g2kun',
        '40S_40W': '1e40jbe1kpadu4a',
        '70N_120W': 'kat0kityhil0udo',
        '40N_60E': 'tfhm8s5v8at0np7',
        '10S_110E': '23u98dlaf4ijfyx',
        '10N_50E': '4k0vr9qphd7zxg8',
        '30N_10E': '70ksdpgfdyw0xx1',
        '10N_10E': 'naw02lg2pnkc3on',
        '40N_70E': 'ovmgwi1ihsskf8w',
        '20N_90W': 'c6df5dqbun2fks6',
        '30S_160E': '4bkneeoybdekmhj',
        '10N_120W': 'd85cl3w5esblmdv',
        '40S_160E': 'eiznsrt6teww45l',
        '50N_70W': '2kkzkjo7wghnh0y',
        '20S_10E': '0higj0z4ufomc7i',
        '40S_120E': 'maodj881wx8mr11',
        '60N_60E': 'q9nk7xu6exy9olg',
        '30S_20E': '8g3og3gnzf8wtcb',
        '30N_20W': 'st34jv53y9uibap',
        '20S_90W': '7ca1iymo44vtapg',
        '50N_140W': 'a8x97yts3pns2zd'
    }
    lon0 += 10 while lon >= lon0 + 10
    lat0 -= 10 while lat <= lat0 - 10
    if lat0 < 0
        lat_str = (-lat0).toString() + 'S'
    else
        lat_str = lat0.toString() + 'N'
    if lon0 < 0
        lon_str = (-lon0).toString() + 'W'
    else
        lon_str = lon0.toString() + 'E'
    tile_name = lat_str + '_' + lon_str
    url = 'https://dl.dropboxusercontent.com/s/' + tile_code[tile_name] + '/tile_' + tile_name + '.bin?dl=1'
    if set_xy
        x = Math.round((lon - lon0) / pix_deg)
        y = Math.round((lat0 - lat) / pix_deg)
        x_deg = lon0 + x * pix_deg
        y_deg = lat0 - y * pix_deg
    return url

import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import sharp from "../../../web/node_modules/sharp/lib/index.js";

const root = path.dirname(fileURLToPath(import.meta.url));
const out = path.join(root, "output");
const W = 1080;
const H = 1350;
const checkedAt = new Date().toISOString();

const carousels = [
  {
    slug: "coffee-gifts",
    sourceGuide: "https://www.wishwave.com/guides/gifts-for-coffee-lovers",
    badge: "COFFEE PEOPLE",
    hook: "5 gifts that make\nevery morning better",
    caption: "Coffee gifts for the person who already has opinions about grind size. Five useful upgrades across five budgets, checked at the merchant before publishing. ☕️ #giftideas #coffeelover #giftmaxxing",
    accent: "#6D4C41",
    style: "editorial",
    products: [
      ["Baratza Encore", "the biggest upgrade for anyone still using a blade grinder", "$149.95", "Baratza", "https://www.baratza.com/en-us/product/encore-zcg485", "https://assets.breville.com/cdn-cgi/image/width=1000,format=png/ZCG410/ZCG410_Hero_DE.png?pdp"],
      ["OutIn Nano", "real espresso for camping, offices and hotel rooms", "$149.99", "OutIn", "https://outin.com/products/nano-portable-espresso-machine-outin-teal", "https://outin.com/cdn/shop/files/0901_nano_5__1.webp?v=1766421638&width=1200"],
      ["Hario V60 set", "a complete pour over ritual in one box", "$46.50", "Hario USA", "https://www.hario-usa.com/products/v60-craft-pour-over-set-colors", "https://www.hario-usa.com/cdn/shop/files/IMG_9528.jpg?v=1757347285&width=1200"],
      ["Trade coffee subscription", "fresh bags matched to how they actually drink coffee", "from $66", "Trade Coffee", "https://www.drinktrade.com/products/coffee-gift-subscription", "https://www.drinktrade.com/cdn/shop/files/12-month_5e56ee12-9051-4d1d-be3d-15acc03b82bd.png?v=1762289704&width=1200"],
      ["Espresso bites", "coffee they can eat on hikes, drives and long afternoons", "$24", "Big Island Coffee Roasters", "https://bigislandcoffeeroasters.com/products/espresso-bites-mixed", "https://bigislandcoffeeroasters.com/cdn/shop/files/Mixed_Espresso_Bites_Big_Island_Coffee_600x.png?v=1782345550"],
    ],
  },
  {
    slug: "anniversary-boyfriend",
    sourceGuide: "https://www.wishwave.com/guides/anniversary-gifts-for-boyfriend",
    badge: "ANNIVERSARY",
    hook: "romantic gifts\nhe will actually use",
    caption: "Anniversary gifts that feel personal without becoming shelf clutter. Pair one useful upgrade with a handwritten note and the gift becomes a memory. ❤️ #anniversarygift #giftideas #giftmaxxing",
    accent: "#A54355",
    style: "paper",
    products: [
      ["BestSelf Intimacy Deck", "a date night conversation starter that creates the memory too", "$27", "BestSelf", "https://bestself.co/products/intimacy-deck", "https://cdn.shopify.com/s/files/1/1015/4487/files/intimacy-deck-card-deck-romantic-connection-529185.jpg?v=1758928240"],
      ["Coco Hinoki candle", "woodsy atmosphere for staying in together", "$44", "Boy Smells", "https://boysmells.com/products/coco-fantome-standard-candle-9oz", "https://boysmells.com/cdn/shop/files/BS_PDP_Standard_Candle_Vessel_Coco_Hinoki_e13222f8-53fc-4edd-8478-78280f179a02.png?v=1778776257&width=1024"],
      ["Front pocket wallet", "a daily carry made personal with initials or your date", "$89", "Popov Leather", "https://www.popovleather.com/products/leather-front-pocket-wallet", "https://www.popovleather.com/cdn/shop/files/leather-front-pocket-wallet-popov-leather-1121197766.jpg?v=1742587542"],
      ["Graza olive oil duo", "a cook together date night that keeps paying off", "$42.98", "Graza", "https://www.graza.co/products/duo-glass", "https://cdn.shopify.com/s/files/1/0550/0003/9638/files/IMAGE_1_Duo-Glass_51f38d4e-9da3-42fb-a95d-01f337657ae9.jpg?v=1762307678"],
      ["Clear cocktail ice mold", "bar style ice for the toast at the end of the night", "$21", "W&P", "https://wandp.com/products/silicone-large-clear-cocktail-ice-cube-mold", "https://wandp.com/cdn/shop/products/WP_VM_Peak_Clear_Ice_01_4x5_Web.jpg?v=1762463330"],
    ],
  },
  {
    slug: "housewarming-gifts",
    sourceGuide: "https://www.wishwave.com/guides/useful-housewarming-gifts",
    badge: "NEW HOME",
    hook: "useful gifts for life\nafter the moving boxes",
    caption: "Housewarming gifts should make the new place easier, warmer or more theirs. Here are five that survive long after the cardboard boxes disappear. 🏡 #housewarming #giftideas #giftmaxxing",
    accent: "#427A66",
    style: "split",
    products: [
      ["Always Pan 2.0", "one good pan for most weeknight meals", "$135", "Our Place", "https://fromourplace.com/products/always-essential-cooking-pan", "https://fromourplace.com/cdn/shop/products/AP_Spice_1.jpg?v=1772474712"],
      ["Clean Essentials kit", "refillable cleaning basics for a fresh start", "$46", "Blueland", "https://www.blueland.com/products/the-clean-essentials", "https://cdn.shopify.com/s/files/1/0057/9158/0227/files/Site_PDP_CleanEssentials_Kit_5.jpg?v=1743109160"],
      ["Little Green cleaner", "the practical hero for rugs, couches and inevitable spills", "$99.99", "Bissell", "https://www.bissell.com/en-us/product/little-green-portable-carpet-upholstery-cleaner-1400B.html", "https://www.bissell.com/dw/image/v2/BDKV_PRD/on/demandware.static/-/Sites-master-catalog-bissell/default/dw2cf2ad67/pwa-hi-res/Product-Images/1400B/1400B_LittleGreen_Packin_1300x1300_9_24.png?sw=1300&sh=1300&sm=fit"],
      ["New Home candle", "a first night ritual that makes the place feel lived in", "$29.95", "Homesick", "https://homesick.com/products/new-home-candle", "https://homesick.com/cdn/shop/files/HMS.NewHome.Ecom.PDP.2.png?v=1764795894"],
      ["Kitchen cutting board", "a useful everyday tool that still feels gift worthy", "$25", "Epicurean", "https://www.epicureancs.com/product/kitchen-series-cutting-board/", "https://epicurean.com/cdn/shop/products/KS1.jpg?v=1664636231"],
    ],
  },
  {
    slug: "beer-lover-gifts",
    sourceGuide: "https://www.wishwave.com/guides/gifts-for-beer-lovers",
    badge: "BEER PEOPLE",
    hook: "beer gifts better than\na novelty pint glass",
    caption: "Five beer gifts that turn the next pour into an experience: better serving, tasting, collecting and even baking. Merchant links and availability checked before publishing. For adults 21+. 🍺 #beergifts #giftideas #giftmaxxing",
    accent: "#B36C28",
    style: "midnight",
    products: [
      ["Fizzics DraftPour", "turns cans and bottles into a smoother draft-style pour", "from $99.99", "Fizzics", "https://store.fizzics.com/products/fizzics-draftpour", "https://store.fizzics.com/cdn/shop/files/DraftPour-Ice-1.png?v=1777479895"],
      ["uKeg Go 64", "keeps a growler pressurized and ready to tap", "$99.99", "GrowlerWerks", "https://growlerwerks.com/products/ukeg-go-64", "https://growlerwerks.com/cdn/shop/files/go64_grey1.png?v=1707346257&width=900"],
      ["Wood USA Beer Cap Map", "turns favorite bottle caps into wall art with a story", "from $37.50", "Beer Cap Maps", "https://www.beercapmaps.com/products/usa-map", "https://cdn.shopify.com/s/files/1/1896/1353/products/Beer_Cap_Map_USA_Hi_Res.JPG?v=1491786516"],
      ["Beer Flight Deck", "a tasting notebook for comparing four pours side by side", "$18", "33 Books", "https://www.33books.com/products/flight-deck-beer-edition", "https://cdn.shopify.com/s/files/1/0245/5185/files/33-books-fb-image.jpg"],
      ["Cornbread & Ale mix", "a warm loaf they activate with their favorite beer", "$10.99", "Soberdough", "https://www.soberdough.com/products/cornbread-ale-new", "https://cdn.shopify.com/s/files/1/0231/2365/products/Soberdough-Cornbread.jpg?v=1523123435"],
    ],
  },
  {
    slug: "graduation-daughter",
    sourceGuide: "https://www.wishwave.com/guides/graduation-gifts-for-daughter",
    badge: "NEXT CHAPTER",
    hook: "graduation gifts for\nwhat comes next",
    caption: "Graduation gifts that honor the work and support the next chapter: one keepsake, one creative memory-maker and three genuinely useful upgrades. 🎓 #graduationgift #giftideas #giftmaxxing",
    accent: "#6557A4",
    style: "editorial",
    products: [
      ["Classic Diploma Frame", "honors the work without adding another disposable keepsake", "$140", "Framebridge", "https://www.framebridge.com/products/the-classic-diploma", "https://www.framebridge.com/cdn/shop/files/080817_FA_Sept_Mailer-008.jpg?v=1715203158"],
      ["Camp Snap 2", "captures the summer without turning every moment into screen time", "$74.95", "Camp Snap", "https://www.campsnapphoto.com/products/camp-snap-2", "https://www.campsnapphoto.com/cdn/shop/files/Yellow_Front_3b38c8a7-b0eb-4b5d-bce3-80f6526bd159.png?v=1781102349"],
      ["Away Carry-On", "useful for visits, interviews and the first independent trips", "$278", "Away", "https://www.awaytravel.com/products/carry-on-misty-purple", "https://www.awaytravel.com/cdn/shop/files/PDP_School_PC_CAR_MistyPurple_02.jpg?v=1783436924"],
      ["Daily Planner", "adds structure when life no longer comes with a syllabus", "$68", "Day Designer", "https://daydesigner.com/products/2026-27-daily-planner-lemon-floral-sage", "https://daydesigner.com/cdn/shop/files/U90Xo7fw.jpg?v=1772746392"],
      ["Birdie personal alarm", "a pocket-sized confidence boost for a new commute or city", "$34.95", "Birdie", "https://www.shesbirdie.com/products/birdie-personal-safety-alarm-3-0", "https://cdn.shopify.com/s/files/1/0259/5808/8792/files/birdie-social.jpg?v=1707225292"],
    ],
  },
  {
    slug: "nurse-gifts",
    sourceGuide: "https://www.wishwave.com/guides/gifts-for-nurses",
    badge: "SHIFT CARE",
    hook: "gifts that respect\na twelve hour shift",
    caption: "Useful nurse gifts for the shift and the recovery afterward. No medical promises, no novelty clutter—just five practical ways to show care. 🩺 #nursegifts #giftideas #giftmaxxing",
    accent: "#2F7488",
    style: "split",
    products: [
      ["Knee-high compression socks", "a polished shift staple with multiple sizes and colors", "$34", "Comrad", "https://www.comradsocks.com/products/knee-high-compression-socks-varsity-1", "https://www.comradsocks.com/cdn/shop/files/KHC-PR-79ZQ_lavender_flat.jpg?v=1778172283"],
      ["Classic Sport Canteen", "one-handed hydration that fits a long shift", "from $40", "Corkcicle", "https://corkcicle.com/products/sport-canteen", "https://corkcicle.com/cdn/shop/files/2020GES-2.png?crop=center&height=1024&v=1785869218&width=1024"],
      ["Manta Sleep Mask", "a blackout rest ritual for sleep at unusual hours", "$39", "Manta Sleep", "https://mantasleep.com/products/manta-sleep-mask", "https://mantasleep.com/cdn/shop/products/1.5-Mask-Buy-Box-1.png?v=1627037557"],
      ["Hypervolt Go 3", "a compact off-duty recovery tool for tired muscles", "$149", "Hyperice", "https://hyperice.com/products/hypervolt-go-3", "https://hyperice.com/cdn/shop/files/Hypervolt-Go-3-pdp-1_02fe1a55-f0c5-4d9c-ae4c-ae9107f701a6.png?v=1780949006&width=1200"],
      ["Lord Bergamot tea", "a calmer post-shift ritual in a giftable tin", "from $13.99", "Smith Teamaker", "https://www.smithtea.com/products/lord-bergamot", "https://www.smithtea.com/cdn/shop/files/Lord-Bergamot-Ingredient-Image-2023.jpg?v=1762439464"],
    ],
  },
  {
    slug: "artist-gifts",
    sourceGuide: "https://www.wishwave.com/guides/gifts-for-artists",
    badge: "ARTISTS",
    hook: "artist gifts without\nguessing their medium",
    caption: "Artist gifts that invite making without pretending you know their exact paint, paper or brush preferences. Five creative tools, each checked at the merchant. 🎨 #artistgifts #giftideas #giftmaxxing",
    accent: "#BD584F",
    style: "paper",
    products: [
      ["Blackwing Essentials Set", "a cult-favorite daily drawing tool in a complete set", "$50", "Blackwing", "https://blackwing602.com/products/blackwing-pencil-essentials-set", "https://blackwing602.com/cdn/shop/files/Essential_Sets-5.jpg?v=1755847519"],
      ["Stone Paper Sketchbook", "an ultra-smooth tree-free surface for pen and pencil", "$25", "Karst", "https://karstgoods.com/products/stone-paper-sketchbook", "https://cdn.shopify.com/s/files/1/1598/4825/files/A6SKETCHBOOK.webp?v=1742465397"],
      ["Tombow Dual Brush Pens", "dual tips and a ready-made palette for lettering or color", "$32.50", "Tombow", "https://www.tombowusa.com/products/dual-brush-pen-art-markers-mermaids-10-pack", "https://www.tombowusa.com/cdn/shop/files/tom_56256_01.jpg?v=1762533504"],
      ["Viviva Colorsheets", "a full watercolor palette that fits in a jacket pocket", "$22", "Viviva", "https://vivivacolors.com/products/original-single-set-16-colors", "https://vivivacolors.com/cdn/shop/files/Amazon_Product_listing.jpg?v=1770030972"],
      ["Original Buddha Board", "paint with water, watch it fade and begin again", "$37.95", "Buddha Board", "https://buddhaboard.com/products/original-buddha-board", "https://buddhaboard.com/cdn/shop/files/OBB_Hero.jpg?v=1768077778"],
    ],
  },
  {
    slug: "runner-gifts",
    sourceGuide: "https://www.wishwave.com/guides/gifts-for-runners",
    badge: "RUNNERS",
    hook: "runner gifts that are\nnot another pair of shoes",
    caption: "Runner gifts are safest when they support the habit without guessing shoe fit. Five training, carry and recovery upgrades across five budgets. 🏃 #runninggifts #giftideas #giftmaxxing",
    accent: "#39756D",
    style: "midnight",
    products: [
      ["OpenRun Pro 2", "open-ear audio leaves the surrounding world audible", "$179.95", "Shokz", "https://shokz.com/products/openrunpro2", "https://shokz.com/cdn/shop/files/LunarWhiteStandard_1.webp?v=1783562552"],
      ["FlipBelt Classic", "carries a phone and keys without a loose armband", "from $44", "FlipBelt", "https://flipbelt.com/products/flipbelt-classic-running-belt", "https://flipbelt.com/cdn/shop/files/5_24258f70-e24f-4ee8-98de-c30fbc0071c2.png?v=1770831935"],
      ["Hidden Comfort Socks", "a cushioned no-show pair that avoids guessing their shoes", "$17", "Balega", "https://balega.com/products/hidden-comfort-no-show-tab", "https://balega.com/cdn/shop/files/xueedfoc4ytz2b6gucu9_1_4.jpg?v=1741879419"],
      ["Forerunner 165", "training data and route tracking without carrying a phone", "$249.99", "Garmin", "https://www.garmin.com/en-US/p/1055469/", "https://res.garmin.com/en/products/010-02863-21/v/cf-lg.jpg"],
      ["GRID 2.0 Foam Roller", "a simple recovery tool for post-run routines", "$74.99", "TriggerPoint", "https://tptherapy.com/products/grid-2-0-foam-roller", "https://tptherapy.com/cdn/shop/files/o7ehc6v550ykxbduixqt.jpg?v=1750694295"],
    ],
  },
  {
    slug: "dog-lover-gifts",
    sourceGuide: "https://www.wishwave.com/guides/gifts-for-dog-lovers",
    badge: "DOG PEOPLE",
    hook: "dog gifts for both ends\nof the leash",
    caption: "The best dog-person gifts are useful for the dog, meaningful for the human, or both. Five picks for walks, play, stories and keepsakes. 🐕 #doglovergifts #giftideas #giftmaxxing",
    accent: "#9A663E",
    style: "editorial",
    products: [
      ["Breed + Health DNA Test", "turns their dog's breed story into a gift they can explore", "$139", "Embark", "https://shop.embarkvet.com/products/breed-and-health-dog-dna-test-kit", "https://cdn.shopify.com/s/files/1/0034/5151/9094/files/DNA_Main_2000x2000_7f5c8368-e7c5-4b75-9cb5-51a0e27accd6.png?v=1774985599"],
      ["Front Range Flex Harness", "an adjustable everyday upgrade for shared walks", "$69.99", "Ruffwear", "https://ruffwear.com/products/front-range-flex-harness", "https://ruffwear.com/cdn/shop/files/Compressed_PNG-3072_Front-Range-Knit-Harness_Polar-Blue_Main_STUDIO_882x589.png?v=1768501123"],
      ["Travel Dog Water Bottle", "portable water for walks, parks and road trips", "$25", "Springer", "https://springlandpets.com/products/22oz-classic-dog-travel-water-bottle", "https://springlandpets.com/cdn/shop/files/84.png?v=1760464519&width=1920"],
      ["Toppl Treat Toy", "a fillable play ritual with three sizes to choose from", "from $20.95", "West Paw", "https://www.westpaw.com/products/toppl-teal", "https://www.westpaw.com/cdn/shop/files/FH083TEL_Small_Toppl_Teal_Unpackaged_Front_Spring26.jpg?v=1775059785&width=2000"],
      ["Custom Pet Portrait", "a personal keepsake that celebrates the dog and their person", "from $48", "West & Willow", "https://westandwillow.com/products/custom-desktop-one-pet-portrait", "https://westandwillow.com/cdn/shop/files/Rudy_-_Black.png?v=1729699453"],
    ],
  },
  {
    slug: "small-brand-home-gifts",
    sourceGuide: "https://www.giftofflist.com/guides/unique-housewarming-gifts-from-small-brands",
    badge: "SMALL BRANDS",
    hook: "housewarming gifts with\na maker behind them",
    caption: "Five small-brand housewarming gifts chosen for daily usefulness, strong design and a real story behind the maker. Merchant pages checked before publishing. 🏡 #smallbusiness #housewarming #giftideas",
    accent: "#A24E36",
    style: "paper",
    products: [
      ["Wylie Hand-Blown Vase", "a sculptural vessel that works with flowers or candlelight", "$75.60", "Everlasting Candle Co.", "https://everlastingcandleco.com/products/wylie-green-x9-wholesale", "https://everlastingcandleco.com/cdn/shop/products/5G2A0319_62eed180-9b24-4ba6-98f1-8262c317999f.jpg?v=1762530414&width=1024"],
      ["Clyde Electric Kettle", "a counter-worthy upgrade for tea, coffee and hosting", "$99.95", "Fellow", "https://fellowproducts.com/products/clyde-electric-kettle", "https://cdn.shopify.com/s/files/1/0057/6235/1219/files/Web_PDP_ClydeElectricKettle_Black_1.png?v=1773352146"],
      ["The Artist Series Set", "olive oils that make pantry storage look like an art shelf", "$160", "Brightland", "https://brightland.co/products/the-artist-series-gift-set", "https://cdn.shopify.com/s/files/1/0020/7978/5023/files/ArtistSeriesGiftSet-1150x1400-1_74ced357-13a6-40b8-964f-6331451a8904.jpg?v=1776360529"],
      ["Diaspora Co. Cookbook", "a signed recipe collection built around diasporic spice traditions", "$35", "Diaspora Co.", "https://www.diasporaco.com/products/the-diaspora-co-cookbook", "https://cdn.shopify.com/s/files/1/0108/8867/5428/files/1_9d363324-93f7-4835-baec-8e66a41bc5c6.jpg?v=1772449212"],
      ["Mini Hot Pot Set", "turns the new kitchen into a communal dinner plan", "$75", "Fly By Jing", "https://flybyjing.com/products/the-hot-pot-starter-set", "https://cdn.shopify.com/s/files/1/0065/8515/5653/files/FBJ-HotpotStarterSet-Hero-1200x1200.png?v=1778258393"],
    ],
  },
  {
    slug: "birdwatcher-gifts",
    sourceGuide: "https://www.giftofflist.com/guides/the-best-gifts-for-birdwatchers-what-birders-actually-want",
    badge: "BIRDWATCHERS",
    hook: "birding gifts they will\nactually take outside",
    caption: "Skip the bird-print mug. These five gifts support spotting, recording and staying comfortable in the field. Merchant availability checked before publishing. 🐦 #birdwatching #outdoorgifts #giftideas",
    accent: "#4E7763",
    style: "split",
    products: [
      ["Standard Issue Binoculars", "compact waterproof optics for backyard and trail sightings", "$99.95", "Nocs Provisions", "https://www.nocsprovisions.com/products/standard-issue-8x25-waterproof-binoculars?variant=47377224073495", "https://cdn.shopify.com/s/files/1/0232/3270/8686/files/Standard-NOC-STD-ALP-main-1000x100017527853275014_21d3caac-d61e-4fb3-9540-61e9862773a4.webp?v=1763398235"],
      ["Sibley Field Diary", "a proper place to record sightings and build a life list", "$22", "Bird Collective", "https://www.birdcollective.com/products/the-sibley-birder-s-life-list-field-diary", "https://cdn.shopify.com/s/files/1/0251/1126/5366/files/the-sibley-birders-life-list-field-diary-817690.jpg?v=1711473126"],
      ["Foldable Backpack Stool", "a seat and carry bag for longer waits at one viewing spot", "$61.99", "Kalsten", "https://kalsten.com/products/noxord-foldable-backpack-stool", "https://cdn.shopify.com/s/files/1/0736/8661/4284/files/14578731-f0b2-4b63-3d28-27d4fd5c1800.png?v=1776941291"],
      ["230° LED Headlamp", "wide hands-free light for early starts and late returns", "$34.95", "NightBuddy", "https://www.nightbuddy.co/products/nightbuddy%E2%84%A2-230-led-headlamp", "https://cdn.shopify.com/s/files/1/0609/9422/4340/files/10_739a6a6d-7c96-4959-a152-3866b4a496d3.png?v=1762458448"],
      ["TeleCular Zoom Lens", "pairs long-range observation with phone photography", "from $129.99", "APEXEL", "https://www.shopapexel.com/products/telecular-3-series-20-60x-zoom-telephoto-lens", "https://cdn.shopify.com/s/files/1/0069/3161/1701/files/T20-60X_1_1500x1500_ec8875ea-a00a-43ab-94cc-422efce8d06e.webp?v=1776066680"],
    ],
  },
  {
    slug: "hiker-gifts",
    sourceGuide: "https://www.giftofflist.com/guides/unique-gifts-for-hikers-25-picks-theyll-actually-use-on-the-trail",
    badge: "TRAIL TEST",
    hook: "hiker gifts that earn\nspace in the pack",
    caption: "A hiking gift has to justify its weight. These five cover comfort, sun, light, water and traction without guessing their boot size. 🥾 #hikinggifts #outdoors #giftideas",
    accent: "#D0603D",
    style: "midnight",
    products: [
      ["Hike Crew Socks", "a useful merino-blend layer with sizes they can exchange", "from $17.50", "Smartwool", "https://www.smartwool.com/en-us/products/hike-crew-socks-sw001614", "https://cdn.shopify.com/s/files/1/0910/5172/1073/files/SW001614100-HERO.jpg?v=1785500828"],
      ["On The Go SPF Set", "portable sun protection for exposed trail days", "$31", "Supergoop!", "https://supergoop.com/products/on-the-go-spf-set", "https://cdn.shopify.com/s/files/1/1503/5658/files/OntheGoSPFSet_01.png?v=1741618869"],
      ["ACTIK CORE Headlamp", "rechargeable trail light for early starts and camp chores", "$87.95", "Petzl", "https://www.petzl.com/US/en/Sport/Headlamps/ACTIK-CORE", "https://www.petzl.com/sfc/servlet.shepherd/version/download/068Tx000006KwpEIAS"],
      ["24oz GeoPress Purifier", "treats water while doubling as the bottle they carry", "$99.95", "GRAYL", "https://grayl.com/products/24oz-geopress-filter-purifier-bottle-covert-edition", "https://cdn.shopify.com/s/files/1/2172/9959/files/GEO_COYOTE_BROWN_STD_1800px_b59f89ab-7244-4fd0-8ea3-5cebfb562fde.png?v=1763347035"],
      ["MICROspikes Traction", "packable winter traction for icy routes and trailheads", "$89.95", "Kahtoola", "https://kahtoola.com/traction/microspikes-footwear-traction/", "https://cdn11.bigcommerce.com/s-m69x292sg4/products/115/images/1133/KT02002-KT02003-KT02004-KT02005---MSredSideBot_0046_copy__43268.1766185825.386.513.jpg?c=1"],
    ],
  },
  {
    slug: "teacher-gifts",
    sourceGuide: "https://www.giftofflist.com/guides/25-unique-teacher-gifts-theyll-actually-use-back-to-school-guide",
    badge: "FOR TEACHERS",
    hook: "teacher gifts beyond\nanother novelty mug",
    caption: "Useful teacher gifts for planning, carrying, refueling and decompressing. Add a specific thank-you note—that is still the most important part. ✏️ #teachergifts #thankyouteacher #giftideas",
    accent: "#315F91",
    style: "editorial",
    products: [
      ["Citron Swirl Notepad", "a small-batch desk upgrade for notes and quick lists", "$25", "Moglea", "https://moglea.com/products/citron-swirl-pad-small", "https://moglea.com/cdn/shop/files/NOT407_CitronSwirlPadSmall_2048px_1024x1024.jpg?v=1751568017"],
      ["Weekly Task Planner", "a structured weekly view for lessons, meetings and life", "from $32", "Appointed", "https://appointed.co/collections/shop-all/products/26-27-weekly-task-planner", "https://cdn.shopify.com/s/files/1/0831/9463/files/26-27_WTP_Hunter.png?v=1776264953"],
      ["Standard BAGGU", "an easy extra carryall for papers, supplies and errands", "$16", "BAGGU", "https://baggu.com/products/standard-baggu-wild-plum", "https://cdn.shopify.com/s/files/1/0851/3262/files/448034d32dfddeeaf1c3464950ea8cb6e339d6bb-2048x2560.jpg?v=1782713045"],
      ["Nitro Cold Brew Case", "a ready-to-grab staff-room or commute refuel", "$45.49", "BLK & Bold", "https://blkandbold.com/products/blk-bold-nitro-cold-brew-coffee-caramel", "https://cdn.shopify.com/s/files/1/0023/2223/5445/files/bnb_RTD_PackTrayCan__NitroCaramel.jpg?v=1687379939"],
      ["Zen Garden Grow Kit", "a small after-school ritual with lavender and chamomile", "$16.99", "Buzzy Seeds", "https://buzzyseeds.com/products/zen-garden-grow-kit-lavender-chamomile", "https://cdn.shopify.com/s/files/1/0605/9137/4512/files/96257_Zen_Garden_WSG_F.png?v=1735677814"],
    ],
  },
  {
    slug: "sustainable-gifts-under-50",
    sourceGuide: "https://www.giftofflist.com/guides/sustainable-gifts-under-50-the-indie-edit-for-thoughtful-planet-friendly-finds",
    badge: "UNDER $50",
    hook: "considered gifts that\nstay under fifty",
    caption: "Five useful under-$50 gifts from independent or design-led brands. We checked price and availability at the merchant rather than trusting an old roundup. 🌿 #giftsunder50 #smallbrands #giftideas",
    accent: "#58734E",
    style: "paper",
    products: [
      ["Faber Literary Tote", "a useful illustrated carryall for books and everyday errands", "$11", "Faber", "https://www.faber.co.uk/product/9780571397983-faber-illustrated-literary-tote-bag/", "https://www.faber.co.uk/wp-content/uploads/2025/04/Faber-Illustrated-Tote-Bag-Blue-credit-Yeshen-Venema-3.jpg"],
      ["Sunday Morning Candle", "a compact coconut-wax ritual with a reusable tin", "$20", "Homebody Candle Co.", "https://www.homebodycandleco.com/products/sunday-morning-candle-tin-homebodycandleco", "https://cdn.shopify.com/s/files/1/0875/2106/files/Sunday_Morning_Candle_Tin_Studio_K6.png?v=1786364680"],
      ["Resurrection Hand Balm", "a frequently used desk or bag upgrade in aluminum packaging", "$35", "Aesop", "https://www.aesop.com/hand-body/hand-washes-balms/resurrection-aromatique-hand-balm/BM06.html", "https://www.aesop.com/dw/image/v2/AANG_PRD/on/demandware.static/-/Sites-aesop-us-master-catalog/default/dwcbe841df/images/products/BM06/ContentEnhancement/Aesop_Hand_Resurrection_Aromatique_Hand_Balm_500mL_Web_Front_2000x2000px.jpg?sw=1400&sh=1400&sm=cut&sfrm=png&q=70&bgcolor=fffef2"],
      ["Daily Stone Lotion Bar", "a waterless lotion bar with a refillable bamboo canister option", "from $14", "Kate McLeod", "https://www.katemcleod.com/products/daily-stone", "https://cdn.shopify.com/s/files/1/0141/1255/5066/files/1-CORE-DAILY-STONE_5546c3fc-dea5-4bfa-9dae-cac618bd4ec8.jpg?v=1762461208"],
      ["Raw Honey Sampler", "three distinct honey profiles for tea, toast and tasting", "$26", "Jacobsen Salt Co.", "https://jacobsensalt.com/products/raw-honey-sampler-set", "https://cdn.shopify.com/s/files/1/0894/6416/files/jacobsen-raw-honey-samper-set.jpg?v=1752791062"],
    ],
  },
].map(c => ({ ...c, products: c.products.map(([name, reason, price, merchant, url, imageUrl]) => ({ name, reason, price, merchant, url, imageUrl })) }));

const esc = s => String(s).replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll("'", "&apos;");
const wrap = (value, max = 26) => {
  const words = value.split(/\s+/); const lines = []; let line = "";
  for (const word of words) {
    if (`${line} ${word}`.trim().length > max && line) { lines.push(line); line = word; }
    else line = `${line} ${word}`.trim();
  }
  if (line) lines.push(line);
  return lines;
};
const lines = (copy, x, y, size, color, weight = 700, max = 28, anchor = "middle", gap = 1.14, family = "Helvetica Neue,Arial,sans-serif") =>
  wrap(copy, max).map((line, i) => `<text x="${x}" y="${y + i * size * gap}" text-anchor="${anchor}" font-family="${family}" font-size="${size}" font-weight="${weight}" fill="${color}">${esc(line)}</text>`).join("");

const themes = {
  editorial: { bg: "#F7F4EF", ink: "#201E1C", muted: "#69635D", card: "#FFFFFF", border: "#E7E1D9", family: "Helvetica Neue,Arial,sans-serif" },
  midnight: { bg: "#11151A", ink: "#F8F5EF", muted: "#B9C0C8", card: "#1C222A", border: "#303843", family: "Helvetica Neue,Arial,sans-serif" },
  paper: { bg: "#EFE3C8", ink: "#382D25", muted: "#74665A", card: "#FFF9EB", border: "#CAB998", family: "Georgia,Times New Roman,serif" },
  split: { bg: "#F7F7F3", ink: "#171A1B", muted: "#62696C", card: "#FFFFFF", border: "#DDE1DF", family: "Helvetica Neue,Arial,sans-serif" },
};
const theme = c => themes[c.style] ?? themes.editorial;
const decoration = c => c.style === "paper"
  ? Array.from({ length: 13 }, (_, i) => `<line x1="0" y1="${210 + i * 76}" x2="1080" y2="${210 + i * 76}" stroke="${c.accent}" stroke-opacity=".09" stroke-width="2"/>`).join("")
  : c.style === "midnight"
    ? `<circle cx="930" cy="120" r="360" fill="${c.accent}" opacity=".20"/><circle cx="105" cy="1135" r="180" fill="${c.accent}" opacity=".10"/>`
    : c.style === "split"
      ? `<rect width="34" height="1350" fill="${c.accent}"/><rect x="34" width="12" height="1350" fill="${c.accent}" opacity=".18"/>`
      : `<circle cx="950" cy="80" r="300" fill="${c.accent}" opacity=".12"/>`;

async function image(url) {
  const response = await fetch(url.replace(/^\/\//, "https://").replace(/^http:/, "https:"), { headers: { "user-agent": "Mozilla/5.0 Giftmaxxing/1.0" } });
  if (!response.ok) throw new Error(`${response.status} ${url}`);
  return sharp(Buffer.from(await response.arrayBuffer())).rotate().resize(760, 650, { fit: "contain", background: "#FFFFFF00" }).png().toBuffer();
}

function chrome(c, index) {
  const t = theme(c);
  const dots = Array.from({ length: 6 }, (_, i) => `<circle cx="${465 + i * 30}" cy="1290" r="${i === index ? 8 : 6}" fill="${i === index ? c.accent : "#D4D0C8"}"/>`).join("");
  return `${dots}<text x="1010" y="1298" text-anchor="end" font-family="Helvetica Neue,Arial,sans-serif" font-size="23" font-weight="600" fill="${t.muted}">${index + 1}/6</text>`;
}

function hookSvg(c) {
  const t = theme(c);
  const badgeFill = c.style === "midnight" ? t.card : c.accent;
  const badgeText = c.style === "midnight" ? c.accent : "#fff";
  return Buffer.from(`<svg width="${W}" height="${H}" xmlns="http://www.w3.org/2000/svg">
    <rect width="${W}" height="${H}" fill="${t.bg}"/>${decoration(c)}
    <rect x="70" y="80" width="300" height="52" rx="${c.style === "split" ? 8 : 26}" fill="${badgeFill}"/><text x="220" y="115" text-anchor="middle" font-family="Helvetica Neue,Arial,sans-serif" font-size="22" font-weight="800" letter-spacing="2" fill="${badgeText}">${esc(c.badge)}</text>
    ${lines(c.hook, 70, 225, c.style === "paper" ? 76 : 72, t.ink, 800, 22, "start", 1.02, t.family)}
    <text x="70" y="475" font-family="Helvetica Neue,Arial,sans-serif" font-size="30" fill="${t.muted}">specific products · live links · zero filler</text>
    ${chrome(c, 0)}
  </svg>`);
}

function productSvg(c, p, index) {
  const t = theme(c);
  const title = lines(p.name, 70, 150, 58, t.ink, 800, 26, "start", 1.02, t.family);
  const reason = lines(p.reason, 70, 1030, 38, t.muted, 500, 42, "start", 1.16, c.style === "paper" ? "Helvetica Neue,Arial,sans-serif" : t.family);
  return Buffer.from(`<svg width="${W}" height="${H}" xmlns="http://www.w3.org/2000/svg">
    <rect width="${W}" height="${H}" fill="${t.bg}"/>${decoration(c)}
    <text x="70" y="72" font-family="Helvetica Neue,Arial,sans-serif" font-size="22" font-weight="800" letter-spacing="2" fill="${c.accent}">${esc(c.badge)}</text>${title}
    <rect x="60" y="285" width="960" height="660" rx="${c.style === "split" ? 10 : 36}" fill="${t.card}" stroke="${t.border}" stroke-width="${c.style === "paper" ? 5 : 2}"/>
    ${reason}<rect x="70" y="1170" width="180" height="58" rx="29" fill="${c.accent}"/><text x="160" y="1209" text-anchor="middle" font-family="Helvetica Neue,Arial,sans-serif" font-size="27" font-weight="800" fill="#fff">${esc(p.price)}</text>
    <text x="275" y="1208" font-family="Helvetica Neue,Arial,sans-serif" font-size="26" font-weight="650" fill="${t.muted}">at ${esc(p.merchant)}</text>${chrome(c, index)}
  </svg>`);
}

async function render(c) {
  const dir = path.join(out, c.slug); const slidesDir = path.join(dir, "slides");
  await fs.mkdir(slidesDir, { recursive: true });
  const productImages = await Promise.all(c.products.map(p => image(p.imageUrl)));
  const tileSize = c.style === "midnight" ? [220, 420] : c.style === "split" ? [420, 280] : [420, 310];
  const tiles = await Promise.all(productImages.slice(0, 4).map(img => sharp(img).resize(tileSize[0], tileSize[1], { fit: "contain", background: theme(c).card }).png().toBuffer()));
  const positions = c.style === "midnight"
    ? tiles.map((input, i) => ({ input, left: 55 + i * 255, top: 635 }))
    : c.style === "split"
      ? tiles.map((input, i) => ({ input, left: 70 + (i % 2) * 470, top: 600 + Math.floor(i / 2) * 300 }))
      : tiles.map((input, i) => ({ input, left: 70 + (i % 2) * 470, top: 565 + Math.floor(i / 2) * 330 }));
  const hookBase = await sharp({ create: { width: W, height: H, channels: 4, background: theme(c).bg } }).composite([
    { input: hookSvg(c) },
    ...positions,
  ]).jpeg({ quality: 94 }).toBuffer();
  await fs.writeFile(path.join(slidesDir, "01.jpg"), hookBase);
  for (let i = 0; i < c.products.length; i++) {
    await sharp({ create: { width: W, height: H, channels: 4, background: theme(c).bg } })
      .composite([{ input: productSvg(c, c.products[i], i + 1) }, { input: productImages[i], left: 160, top: 290 }])
      .jpeg({ quality: 94, chromaSubsampling: "4:4:4" }).toFile(path.join(slidesDir, `${String(i + 2).padStart(2, "0")}.jpg`));
  }
  const thumbs = await Promise.all(Array.from({ length: 6 }, async (_, i) => ({ input: await sharp(path.join(slidesDir, `${String(i + 1).padStart(2, "0")}.jpg`)).resize(216, 270).jpeg().toBuffer(), left: i * 216, top: 0 })));
  await sharp({ create: { width: 1296, height: 270, channels: 3, background: "#EDE9E3" } }).composite(thumbs).jpeg({ quality: 92 }).toFile(path.join(dir, "contact-sheet.jpg"));
  const manifest = { id: `editorial-${c.slug}-v1`, title: c.hook.replace("\n", " "), caption: c.caption, sourceGuide: c.sourceGuide, checkedAt, status: "prototype_review_required", products: c.products, slides: Array.from({ length: 6 }, (_, i) => ({ index: i, file: `slides/${String(i + 1).padStart(2, "0")}.jpg` })) };
  await fs.writeFile(path.join(dir, "app-manifest.json"), `${JSON.stringify(manifest, null, 2)}\n`);
  await fs.writeFile(path.join(dir, "caption.txt"), `${c.caption}\n`);
  await fs.writeFile(path.join(dir, "reference-analysis.json"), `${JSON.stringify({ reference: { source: c.sourceGuide, cardCount: 6, dimensions: { width: W, height: H }, aspectRatio: "4:5" }, opening: { role: "hook", differenceFromBody: "four-product visual grid", text: c.hook, position: "upper left", treatment: `${c.style} layout with category accent` }, cards: [{ index: 1, role: "hook", content: c.hook }, ...c.products.map((p, i) => ({ index: i + 2, role: "product proof", content: p.name, shotType: "merchant product image", text: { present: true }, searchIntent: p.url }))], invariants: ["one product per body card", "live merchant link", "original copy", "price checked before publish", "no visible app branding"], variability: ["recipient", "occasion", "accent color", "layout family", "type style"], selectionRule: "Only merchant-verified products survive manual visual review." }, null, 2)}\n`);
}

await fs.mkdir(out, { recursive: true });
for (const c of carousels) await render(c);
console.log(`Rendered ${carousels.length} carousels to ${out}`);

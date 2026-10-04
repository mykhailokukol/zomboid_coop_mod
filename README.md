# CO-OP — Project Zomboid mod (Build 42)

Co-op tools for a shared base: a shared checklist of skill books, magazines and VHS
tapes, map marks shared automatically, pings everyone can see, a shared to-do list, a
choice of where crafted and removed items land, an Organization skill that makes
containers hold more, a cart to pull loads home, and wear colours behind the
hotbar.

Every feature has its own on/off switch in the sandbox options, so you can take only
the parts you want.

**[English](#english) · [Українська](#українська) · [Русский](#русский)**

---

## English

### What it does

- **Books at home** — a shared checklist of skill books, recipe magazines and
  skill-teaching VHS tapes. One player marks an item as "at home", everyone on the
  server sees it, with who marked it, when, and an optional note ("Rosewood, top shelf").
  Marked items get a **white check mark** in the inventory; read books keep the green one.
  Right-clicking a shelf or a crate in the world marks everything inside it at once,
  bags packed in it included.
- **Shared map marks** — an **MP** tick box on the map drawing panel, on by default.
  Everything you draw is shared with all players the moment you place it.
- **Pings** — press **Ping** (middle mouse by default) on the open map or anywhere in
  the world and everyone on the server sees the spot for a few seconds: a patch on the
  ground, an arrow at the edge of the screen pointing at it, your name above it and a
  line in chat. What was under the cursor picks the icon and the colour — a zombie, a
  player, a car, a body, loose loot, or a plain spot in your own colour.
- **Shared to-do list** — one list for the whole server in its own window on **[**.
  Anyone can add a line, tick it off, edit it or delete it, and every line remembers who
  wrote it and who finished it. Changes other people make are announced in chat, so the
  list gets noticed without anyone opening it.
- **Item output destination** — where new items go: your hands, your bags, a container
  next to you, or the ground. Cooking, carpentry, car mechanics and smithing each get
  their own setting, plus a default for everything else. Applies to crafting and to
  parts you take off a vehicle.
- **Organization skill** — a skill from 0 to 10 replacing the Organized / Disorganized
  traits. It raises the capacity of containers you organise (permanently, for everyone)
  and how fast you move items. Trained by the weight you move through storage.
- **Push a vehicle** — stand at the front or the back of a car or a trailer, press
  **V** and pick **Push**. How fast it rolls depends on what it weighs — up to 10 km/h
  for a trailer or a small car, 7 for an ordinary one, 4 for a van or a truck — and you
  go along with
  your hands on the bodywork until you press **Esc**. It will not budge a car somebody
  is sitting behind the wheel of, one with the engine running, or one missing a wheel;
  a burnt-out wreck is fair game.
- **Digging clay** — with a shovel on you, right-click the ground next to a river or a
  lake and pick **Dig for clay**. It digs like a garden plot — same effort, same noise —
  and gives you one to eleven lumps of clay depending on your Pottery, plus 10
  Pottery XP. A patch of bank you have dug gives nothing for a week, and everyone on
  the server shares that: two people cannot work the same spot twice.
- **Cart** — build one out of 5 planks, 10 nails and two tires of the same
  kind (Carpentry 5, Mechanics 1, with a hammer, a saw and a lug wrench). Right-click it
  on the ground and **Attach cart**: it takes a slot of its own, so your backpack stays
  on, and rolls along behind you, where everyone can see it. It weighs nothing itself
  and holds 50 kg, none of which you carry — but every 20 kg inside slows you down by 15%. While it is attached you
  cannot climb fences or windows or get into a car; **Detach cart** parks it where you
  stand, and anyone can open it there. A cart is never carried in your hands or your
  bags. Parked, the load still counts towards the 50 kg the game allows on one tile of
  floor, so park it where nothing else is lying.
- **Digging a well** — in the Build window under Outdoors, at Masonry 6: 30 stone
  blocks, a long stick, two small handles, any empty bucket, a rope (or twine, or a
  sheet rope) and three empty sacks, with any shovel. What you get is the game's own
  well — 10,000 l of clean water, topped up by rain — plus your shovel back and three
  sacks of dirt. Gives 80 Masonry and 15 Carpentry XP.
- **Audiobooks** — right-click a desktop computer that has power (the grid or a
  generator) → **Computer**: burn a skill book onto a blank CD (an in-game hour, the
  book stays with you), or wipe any CD back to blank (15 minutes). An audiobook plays
  in anything a music CD plays in — a CD player, a radio that takes discs, a car radio
  — and listening to it counts as reading the book: it takes as long as reading would
  (the *minutes per page* sandbox setting and the reader traits included), the pages
  heard go onto that book's page count, and the XP multiplier grows with them. Everyone
  within five tiles of a radio hears it; a CD player in your hands is just for you. The
  volume has to suit your level, as with the book.
- **Hotbar condition colours** — a hotbar slot holding a worn item gets its background
  split into a coloured column per state the item has: condition, head and sharpness,
  green above 75%, yellow down to 25%, red below. An item in good shape draws nothing,
  so the hotbar only lights up when something needs attention. Local only, nothing is
  sent anywhere.
- **Recipe information** — the crafting window shows what a recipe gives you before you
  make it: the XP it awards and, for a weapon, a tool or a piece of clothing, the stats
  the finished item will have (condition, damage, sharpness, defenses, insulation),
  drawn as bars the way the item's own tooltip draws them. The same row appears in the
  Build window, at crafting benches and workbenches, and in the window of a machine such
  as a drying rack, a kiln or a furnace.
- **Batch crafting** — the quantity box and the MAX button are back on the clothing and
  bag recipes the base game makes you craft one at a time. Repairs, filter swaps and
  anything else that changes an item you already hold stay one at a time.

### Requirements

Project Zomboid **Build 42**. Works in single player, in a hosted "My Server" game and
on a dedicated server.

### Install without the Steam Workshop

1. Download this repository — green **Code** button → **Download ZIP** — and unpack it.
   (Or `git clone https://github.com/mykhailokukol/zomboid_coop_mod.git`.)

2. Copy the **`CO-OP`** folder from `mods/` into your Project Zomboid user folder:

   | System | Path |
   |---|---|
   | Windows | `C:\Users\<you>\Zomboid\mods\` |
   | Linux | `~/Zomboid/mods/` |
   | macOS | `~/Zomboid/mods/` |

3. Check the result. `mod.info` must sit **inside** the `42` folder — that is what
   tells Build 42 the mod is for this build:

   ```
   Zomboid/mods/CO-OP/
   └── 42/
       ├── mod.info
       ├── poster.png
       └── media/
   ```

4. Start the game, open **MODS** in the main menu, tick **CO-OP**, press **DONE**.

5. Mods are remembered per save, so when you create or load a world, check
   **Choose Mods...** there too.

### If you had the Steam Workshop version

The mod used to be on the Workshop as *Coop Quality of Life*. That version is no longer
updated, and it must go before you install this one: both are called `CO-OP`, the game
loads only one of them, and it may well pick the old one - the new version then looks
installed but none of its changes are there.

1. Quit the game completely.
2. In Steam, open the Workshop page of *Coop Quality of Life* and press
   **Unsubscribe** (or Steam → Library → Project Zomboid → Workshop → *Coop Quality of
   Life* → Unsubscribe).
3. Delete the folder Steam may leave behind:
   `C:\Program Files (x86)\Steam\steamapps\workshop\content\108600\3803601902`.
4. If you ever uploaded the mod yourself, move `Zomboid/Workshop/CoopQoL` out of the
   `Zomboid` folder: the game reads mods from there as well.
5. On a hosted or dedicated server, empty the `WorkshopItems=` line in
   `Zomboid/Server/<name>.ini` (keep `Mods=CO-OP`).
6. Install as described above.

Your world is safe: book marks, the to-do list and everything else live in the save,
not in the mod folder, and the mod id has not changed.

To check which copy the game loaded, open `Zomboid/console.txt` after the main menu
appears: the `[CO-OP] ...` lines list the features that started, and
`recipe info row installed` means it is the current version.

### Multiplayer

Everyone needs the same folder — the mod is not on the Workshop, so it cannot download
itself, and a player without it cannot join.

On a hosted server the mod must also be enabled **in the server settings**, not only in
your client mod list:

1. Main menu → **HOST** → **Manage settings...**
2. Pick your settings → **Edit Selected Settings**
3. Open the **Mods** group on the left
4. Under *Add an installed mod to the list*, choose **CO-OP**
5. Save, go back, **START**

That writes `Mods=CO-OP` into `Zomboid/Server/<name>.ini`, which you can also edit by
hand. For a dedicated server: put the folder in the server's `Zomboid/mods/`, add
`CO-OP` to the `Mods=` line, restart.

### Settings

Everything is in the sandbox options, on a **CO-OP** page of their own: in a solo game
on the world creation screen, on a server under **Manage settings... → Edit Selected
Settings**. There is an on/off switch per feature — switching one off leaves the vanilla
behaviour, not a half-working mod — plus how long a ping lives, the cooldown between two
pings from the same player, whether pings and to-do changes are announced in chat, the
Organization XP rate, how many lines the to-do list will hold, the three speeds a
vehicle can be pushed at, and how long a dug patch of riverbank takes to give clay again
(with the XP and the amount it gives).

Settings are read as they are used, so changing one on a running server reaches everyone
without a reload. Containers the Organization skill has already enlarged keep their size
if you switch it off later.

### Using it

| Feature | How |
|---|---|
| Mark a book | Right-click it → **Books at home** → *Mark as at home* |
| Mark a whole shelf | Right-click the shelf or crate in the world → *Mark all as at home* |
| Open the checklist | **K** (rebindable under Options → Keybindings, section *Books At Home*) |
| Share map marks | Open the map, keep the **MP** box ticked |
| Ping a spot | **Middle mouse** in the world or on the open map (rebindable under Options → Keybindings, section *CO-OP*) |
| Open the to-do list | **[** (same section) |
| Choose where items go | The drop-down under the **Craft** button, or under the part lists in the vehicle mechanics window |
| Organization skill | In the character skills panel, under Crafting |
| Push a vehicle | Stand at its front or back → **V** → *Push*. **Esc** to let go |
| Dig clay | Carry a shovel → right-click the ground within a tile of a river or lake → *Dig for clay* |
| Dig a well | Build window → *Outdoors* → *Well* |
| Burn an audiobook | Right-click a computer with power → *Computer* → *Burn an audiobook* |
| Turn a feature off | Sandbox options → **CO-OP** |

### Updating

Quit the game **to the desktop** - the mod's code is read when the game starts, so going
back to the main menu is not enough - replace the `CO-OP` folder with the new one and
start again. On a server, restart the server too: it runs its own copy of the mod. Every
player needs the same version.

### Uninstalling

Delete `Zomboid/mods/CO-OP`. Book marks and the to-do list live in the world save and
are simply ignored once the mod is gone.

---

## Українська

### Що це

- **Книги вдома** — спільний список книг навичок, журналів рецептів і касет, що вчать
  навичок. Один гравець позначає предмет як «вдома», і це бачать усі на сервері: хто
  позначив, коли, і необов'язкова нотатка («Роузвуд, верхня полиця»). Позначені
  предмети отримують **білу галочку** в інвентарі; прочитані книги залишають зелену.
  ПКМ по полиці чи ящику у світі позначає все, що всередині, разом із вкладеними
  сумками.
- **Спільні позначки на карті** — прапорець **MP** на панелі малювання карти, увімкнений
  за замовчуванням. Усе, що ви малюєте, одразу бачать усі гравці.
- **Мітки (пінги)** — натисніть **Мітка** (за замовчуванням середня кнопка миші) на
  відкритій карті або будь-де у світі, і всі на сервері кілька секунд бачать це місце:
  пляму на землі, стрілку з краю екрана, ваше ім'я над міткою та рядок у чаті. Те, що
  було під курсором, визначає значок і колір — зомбі, гравець, автівка, тіло, лут або
  просто місце вашим власним кольором.
- **Спільний список справ** — один список на весь сервер, в окремому вікні на **[**.
  Будь-хто може додати рядок, позначити виконаним, змінити чи видалити його; кожен рядок
  пам'ятає, хто його написав і хто його закрив. Про чужі зміни пишеться рядок у чаті,
  тож список помітний, навіть якщо ніхто не відкриває вікно.
- **Куди складати нові предмети** — у руки, у сумки, у контейнер поруч або на землю.
  Кулінарія, столярство, автомеханіка та ковальство мають власне налаштування, плюс
  типове для всього іншого. Діє і для крафту, і для знятих з машини деталей.
- **Навичка «Організація»** — навичка від 0 до 10, що замінює риси «Організований» /
  «Неорганізований». Збільшує місткість контейнерів, які ви впорядковуєте (назавжди, для
  всіх), і швидкість перекладання речей. Зростає від ваги, яку ви переносите крізь
  сховища.
- **Штовхати машину** — станьте спереду або ззаду автівки чи причепа, натисніть **V**
  і виберіть **Штовхати**. Швидкість залежить від ваги — до 10 км/год для причепа
  чи невеликої автівки, 7 для звичайної, 4 для фургона чи вантажівки — а ви йдете поряд,
  спершись на кузов, доки не натиснете **Esc**. Не зрушить автівку, за кермом якої хтось
  сидить, із запущеним двигуном або без колеса; згорілий каркас штовхати можна.
- **Копання глини** — маючи лопату, натисніть ПКМ по землі біля річки чи озера і
  виберіть **Копати глину**. Копається так само, як грядка — та сама втома, той самий
  шум — і дає від однієї до одинадцяти грудок глини залежно від гончарства, а також
  10 одиниць досвіду гончарства. Викопана ділянка берега тиждень нічого не дає, і це
  спільне для всього сервера: двоє не викопають одне й те саме місце двічі.
- **Візок** — збирається з 5 дощок, 10 цвяхів і двох однакових шин (Теслярство 5,
  Механіка 1, потрібні молоток, пила й балонний ключ). ПКМ по візку на землі →
  **Причепити візок**: у нього власний слот, тож рюкзак лишається на спині, а візок
  котиться позаду, і його бачать усі. Сам нічого не важить, вміщує 50 кг, і вантаж ви
  не несете — зате кожні 20 кг вантажу сповільнюють на 15%. Поки візок причеплений, не можна лізти через паркани й вікна та
  сідати в машину; **Відчепити візок** ставить його там, де ви стоїте, і тоді відкрити
  його може будь-хто. У руках чи в сумці візок не носять. На землі вантаж рахується до
  50 кг, які гра дозволяє на одну клітинку підлоги, тож ставте його там, де нічого не лежить.
- **Криниця** — у вікні будівництва, розділ Outdoors, з Мулярством 6: 30 кам'яних
  блоків, довга палиця, дві короткі руків'я, будь-яке порожнє відро, мотузка (або
  бечівка, або мотузка з простирадл) і три порожні мішки, плюс будь-яка лопата.
  Виходить звичайна ігрова криниця — 10 000 л чистої води, що поповнюється дощем, —
  а ще лопата повертається і три мішки землі. Дає 80 досвіду Мулярства і 15 Теслярства.
- **Аудіокниги** — ПКМ по комп'ютеру з живленням (мережа чи генератор) → **Комп'ютер**:
  записати книгу навички на чистий CD (ігрова година, книга лишається у вас) або стерти
  будь-який CD до чистого (15 хвилин). Аудіокнига грає всюди, де грає звичайний CD, —
  у плеєрі, радіо з дисководом, автомагнітолі, — а прослуховування зараховується як
  читання: триває стільки ж (з урахуванням налаштування *хвилин на сторінку* й рис
  читача), прослухані сторінки додаються до лічильника цієї книги, і разом із ними росте
  множник досвіду. Радіо чують усі в радіусі п'яти клітинок; плеєр у руках — лише ви.
  Том має відповідати вашому рівню, як і книга.
- **Смуги стану на панелі швидкого доступу** — комірка з надягнутим предметом ділить тло
  на кольорові смуги, по одній на кожен стан предмета: міцність, стан голівки та
  гострота, зелений понад 75%, жовтий до 25%, нижче червоний. Справний предмет не малює
  нічого, тож панель світиться лише тоді, коли щось потребує уваги. Суто локально,
  нікуди не передається.
- **Інформація про рецепт** — вікно крафту показує, що дасть рецепт, ще до виготовлення:
  скільки досвіду він дає, а для зброї, інструмента чи одягу — характеристики готового
  предмета (міцність, шкода, гострота, захист, утеплення) смугами, як у підказці самого
  предмета. Той самий рядок є у вікні будівництва, біля верстатів і робочих столів та у
  вікні пристроїв на кшталт сушарки, печі для випалу чи горна.
- **Крафт партіями** — поле кількості й кнопка MAX повертаються рецептам одягу та сумок,
  які базова гра змушує робити по одній речі. Ремонт, заміна фільтрів і все, що змінює
  вже наявний предмет, лишаються поштучними.

### Вимоги

Project Zomboid **Build 42**. Працює в одиночній грі, на «своєму сервері» та на
виділеному сервері.

### Встановлення без Steam Workshop

1. Завантажте репозиторій — зелена кнопка **Code** → **Download ZIP** — і розпакуйте.
   (Або `git clone https://github.com/mykhailokukol/zomboid_coop_mod.git`.)

2. Скопіюйте теку **`CO-OP`** з `mods/` у теку користувача Project Zomboid:

   | Система | Шлях |
   |---|---|
   | Windows | `C:\Users\<ви>\Zomboid\mods\` |
   | Linux | `~/Zomboid/mods/` |
   | macOS | `~/Zomboid/mods/` |

3. Перевірте результат. `mod.info` має лежати **всередині** теки `42` — саме це каже
   Build 42, що мод для цієї версії:

   ```
   Zomboid/mods/CO-OP/
   └── 42/
       ├── mod.info
       ├── poster.png
       └── media/
   ```

4. Запустіть гру, у головному меню відкрийте **МОДИ**, увімкніть **CO-OP**, натисніть
   **ГОТОВО**.

5. Список модів зберігається для кожного світу окремо, тож під час створення або
   завантаження світу перевірте також **«Вибрати моди...»**.

### Якщо у вас була версія зі Steam Workshop

Раніше мод був у Workshop як *Coop Quality of Life*. Та версія більше не оновлюється, і
її треба прибрати перед встановленням цієї: обидві називаються `CO-OP`, гра завантажує
лише одну з них і цілком може обрати стару - тоді нова версія ніби встановлена, але
жодних її змін у грі немає.

1. Повністю вийдіть із гри.
2. У Steam відкрийте сторінку *Coop Quality of Life* у Workshop і натисніть
   **Відписатися** (або Steam → Бібліотека → Project Zomboid → Workshop → *Coop Quality
   of Life* → Відписатися).
3. Видаліть теку, яку Steam може залишити:
   `C:\Program Files (x86)\Steam\steamapps\workshop\content\108600\3803601902`.
4. Якщо ви колись самі завантажували мод у Workshop, перенесіть `Zomboid/Workshop/CoopQoL`
   за межі теки `Zomboid`: гра читає моди і звідти.
5. На своєму чи виділеному сервері очистьте рядок `WorkshopItems=` у
   `Zomboid/Server/<назва>.ini` (`Mods=CO-OP` залиште).
6. Встановіть мод, як описано вище.

Світ не постраждає: позначки книг, список справ і все інше зберігаються у сейві, а не в
теці мода, а ідентифікатор мода не змінився.

Щоб перевірити, яку копію завантажила гра, відкрийте `Zomboid/console.txt`, коли
з'явиться головне меню: рядки `[CO-OP] ...` перелічують функції, що запустилися, а
`recipe info row installed` означає, що це поточна версія.

### Мультиплеєр

Однакова тека потрібна всім — мода немає у Workshop, сам він не завантажиться, і без
нього гравець не зайде на сервер.

На своєму сервері мод треба увімкнути ще й **у налаштуваннях сервера**, а не лише в
клієнтському списку модів:

1. Головне меню → **СВІЙ СЕРВЕР** → **«Налаштування...»**
2. Виберіть налаштування → **«Редагувати вибрані налаштування»**
3. Зліва відкрийте групу **«Моди»**
4. У рядку *«Додати встановлений мод до списку»* виберіть **CO-OP**
5. Збережіть, поверніться, **ЗАПУСТИТИ**

Це запише `Mods=CO-OP` у `Zomboid/Server/<назва>.ini` — цей файл можна редагувати й
вручну. Для виділеного сервера: покладіть теку в `Zomboid/mods/` сервера, додайте
`CO-OP` до рядка `Mods=`, перезапустіть.

### Налаштування

Усе живе в пісочниці (sandbox), на власній сторінці **CO-OP**: в одиночній грі — на
екрані створення світу, на сервері — у **«Налаштування...» → «Редагувати вибрані
налаштування»**. Там є вимикач для кожної можливості (вимкнена можливість повертає
звичайну поведінку гри, а не половину мода), а також час життя мітки, затримка між
мітками одного гравця, оголошення міток і змін списку справ у чаті, швидкість досвіду
«Організації», межа довжини списку справ, три швидкості, з якими можна штовхати
машину, і час, за який викопана ділянка берега знову дає глину (разом із досвідом і
кількістю глини).

Налаштування читаються в момент використання, тож зміна на запущеному сервері доходить
до всіх без перезаходу. Контейнери, які «Організація» вже збільшила, зберігають свій
розмір, навіть якщо згодом її вимкнути.

### Як користуватися

| Можливість | Як |
|---|---|
| Позначити книгу | ПКМ по книзі → **Книги вдома** → *Позначити: вдома* |
| Позначити цілу полицю | ПКМ по полиці чи ящику у світі → *Позначити все як «вдома»* |
| Відкрити список книг | **K** (змінюється: Налаштування → Керування, розділ *Books At Home*) |
| Ділитися позначками карти | Відкрийте карту, залиште прапорець **MP** увімкненим |
| Поставити мітку | **Середня кнопка миші** у світі або на відкритій карті (змінюється: Налаштування → Керування, розділ *CO-OP*) |
| Відкрити список справ | **[** (той самий розділ) |
| Куди складати предмети | Випадний список під кнопкою **Створити** або під списками деталей у вікні механіки |
| Навичка «Організація» | У панелі навичок персонажа, у групі «Створення» |
| Штовхати машину | Станьте спереду чи ззаду → **V** → *Штовхати*. **Esc**, щоб відпустити |
| Копати глину | Візьміть лопату → ПКМ по землі за крок від річки чи озера → *Копати глину* |
| Викопати криницю | Вікно будівництва → *Outdoors* → *Криниця* |
| Записати аудіокнигу | ПКМ по комп'ютеру з живленням → *Комп'ютер* → *Записати аудіокнигу* |
| Вимкнути можливість | Налаштування пісочниці → **CO-OP** |

### Оновлення

Вийдіть із гри **на робочий стіл** - код мода читається під час запуску гри, тож
повернутися в головне меню недостатньо - замініть теку `CO-OP` новою і запустіть гру
знову. На сервері перезапустіть і сервер: він використовує власну копію мода. Версія
має бути однакова в усіх гравців.

### Видалення

Видаліть `Zomboid/mods/CO-OP`. Позначки книг і список справ зберігаються у світі та
просто ігноруються без мода.

---

## Русский

### Что это

- **Книги дома** — общий список книг навыков, журналов рецептов и кассет, обучающих
  навыкам. Один игрок отмечает предмет как «дома», и это видят все на сервере: кто
  отметил, когда, и необязательная заметка («Роузвуд, верхняя полка»). Отмеченные
  предметы получают **белую галочку** в инвентаре; прочитанные книги сохраняют зелёную.
  ПКМ по полке или ящику в мире отмечает всё, что внутри, вместе с вложенными сумками.
- **Общие отметки на карте** — флажок **MP** на панели рисования карты, включён по
  умолчанию. Всё, что вы рисуете, сразу видят все игроки.
- **Метки (пинги)** — нажмите **Метка** (по умолчанию средняя кнопка мыши) на открытой
  карте или где угодно в мире, и все на сервере несколько секунд видят это место: пятно
  на земле, стрелку с края экрана, ваше имя над меткой и строку в чате. То, что было под
  курсором, задаёт значок и цвет — зомби, игрок, машина, тело, лут или просто место
  вашим собственным цветом.
- **Общий список дел** — один список на весь сервер, в отдельном окне на **[**. Любой
  может добавить строку, отметить её выполненной, изменить или удалить; каждая строка
  помнит, кто её написал и кто её закрыл. О чужих изменениях пишется строка в чате,
  поэтому список заметен, даже если никто не открывает окно.
- **Куда складывать новые предметы** — в руки, в сумки, в контейнер рядом или на землю.
  У кулинарии, столярки, автомеханики и кузнечного дела своя настройка, плюс общая для
  всего остального. Работает и для крафта, и для снятых с машины деталей.
- **Навык «Организация»** — навык от 0 до 10, заменяющий черты «Организованный» /
  «Неорганизованный». Увеличивает вместимость контейнеров, которые вы разбираете
  (навсегда, для всех), и скорость перекладывания вещей. Растёт от веса, который вы
  переносите через хранилища.
- **Толкать машину** — встаньте спереди или сзади автомобиля либо прицепа, нажмите
  **V** и выберите **Толкать**. Скорость зависит от веса — до 10 км/ч для прицепа
  или небольшой машины, 7 для обычной, 4 для фургона или грузовика — а вы идёте рядом,
  упершись в кузов, пока не нажмёте **Esc**. Не сдвинет машину, за рулём которой кто-то
  сидит, с заведённым двигателем или без колеса; сгоревший остов толкать можно.
- **Копание глины** — с лопатой в сумке нажмите ПКМ по земле у реки или озера и
  выберите **Копать глину**. Копается так же, как грядка — та же усталость, тот же шум —
  и даёт от одной до одиннадцати горстей глины в зависимости от гончарного дела, плюс
  10 единиц опыта гончарного дела. Выкопанный участок берега неделю ничего не даёт, и
  это общее для всего сервера: двое не выкопают одно и то же место дважды.
- **Тележка** — собирается из 5 досок, 10 гвоздей и двух одинаковых шин
  (Плотничество 5, Механика 1, нужны молоток, пила и баллонный ключ). ПКМ по тележке на
  земле → **Прицепить тележку**: у неё свой слот, так что рюкзак остаётся на спине, а
  тележка катится сзади, и её видят все. Сама ничего не весит, вмещает 50 кг, и груз вы
  не несёте — зато каждые 20 кг груза замедляют на 15%. Пока тележка прицеплена, нельзя лезть через заборы и окна и садиться в
  машину; **Отцепить тележку** ставит её там, где вы стоите, и тогда открыть её может
  кто угодно. В руках или в сумке тележку не носят. На земле груз считается в те 50 кг,
  которые игра разрешает на одну клетку пола, так что ставьте её там, где ничего не лежит.
- **Колодец** — в окне постройки, раздел «Наружное», с Каменной кладкой 6: 30 каменных
  блоков, длинная палка, две короткие рукояти, любое пустое ведро, верёвка (или бечёвка,
  или тряпичная верёвка) и три пустых мешка, плюс любая лопата. Получается обычный
  игровой колодец — 10 000 л чистой воды, пополняемой дождём, — а ещё лопата
  возвращается и три мешка земли. Даёт 80 опыта Каменной кладки и 15 Плотничества.
- **Аудиокниги** — ПКМ по компьютеру с питанием (сеть или генератор) → **Компьютер**:
  записать книгу навыка на чистый CD (игровой час, книга остаётся у вас) или стереть
  любой CD до чистого (15 минут). Аудиокнига играет везде, где играет обычный CD, —
  в плеере, радио с дисководом, автомагнитоле, — а прослушивание засчитывается как
  чтение: длится столько же (с учётом настройки *минут на страницу* и черт читателя),
  прослушанные страницы прибавляются к счётчику этой книги, и вместе с ними растёт
  множитель опыта. Радио слышат все в пяти клетках; плеер в руках — только вы. Том
  должен подходить вашему уровню, как и книга.
- **Полосы состояния на панели быстрого доступа** — ячейка с надетым предметом делит фон
  на цветные полосы, по одной на каждое состояние предмета: прочность, состояние головки
  и заточка, зелёный выше 75%, жёлтый до 25%, ниже красный. Исправный предмет не рисует
  ничего, поэтому панель светится только тогда, когда что-то требует внимания. Чисто
  локально, никуда не передаётся.
- **Информация о рецепте** — окно крафта показывает, что даст рецепт, ещё до
  изготовления: сколько опыта он даёт, а для оружия, инструмента или одежды —
  характеристики готового предмета (прочность, урон, заточка, защита, утепление)
  полосами, как в подсказке самого предмета. Та же строка есть в окне строительства, у
  верстаков и рабочих столов и в окне устройств вроде сушилки, печи для обжига или горна.
- **Крафт партиями** — поле количества и кнопка MAX возвращаются рецептам одежды и сумок,
  которые базовая игра заставляет делать по одной вещи. Ремонт, замена фильтров и всё,
  что меняет уже имеющийся предмет, остаются поштучными.

### Требования

Project Zomboid **Build 42**. Работает в одиночной игре, на «своём сервере» и на
выделенном сервере.

### Установка без Steam Workshop

1. Скачайте репозиторий — зелёная кнопка **Code** → **Download ZIP** — и распакуйте.
   (Или `git clone https://github.com/mykhailokukol/zomboid_coop_mod.git`.)

2. Скопируйте папку **`CO-OP`** из `mods/` в пользовательскую папку Project Zomboid:

   | Система | Путь |
   |---|---|
   | Windows | `C:\Users\<вы>\Zomboid\mods\` |
   | Linux | `~/Zomboid/mods/` |
   | macOS | `~/Zomboid/mods/` |

3. Проверьте результат. `mod.info` должен лежать **внутри** папки `42` — именно это
   говорит Build 42, что мод для этой версии:

   ```
   Zomboid/mods/CO-OP/
   └── 42/
       ├── mod.info
       ├── poster.png
       └── media/
   ```

4. Запустите игру, в главном меню откройте **МОДЫ**, включите **CO-OP**, нажмите
   **ГОТОВО**.

5. Список модов сохраняется для каждого мира отдельно, поэтому при создании или
   загрузке мира проверьте также **«Выбрать моды...»**.

### Если у вас была версия из Steam Workshop

Раньше мод был в Workshop как *Coop Quality of Life*. Та версия больше не обновляется, и
её нужно убрать перед установкой этой: обе называются `CO-OP`, игра загружает только
одну из них и вполне может выбрать старую - тогда новая версия вроде бы установлена, но
никаких её изменений в игре нет.

1. Полностью выйдите из игры.
2. В Steam откройте страницу *Coop Quality of Life* в Workshop и нажмите
   **Отписаться** (или Steam → Библиотека → Project Zomboid → Workshop → *Coop Quality
   of Life* → Отписаться).
3. Удалите папку, которую Steam может оставить:
   `C:\Program Files (x86)\Steam\steamapps\workshop\content\108600\3803601902`.
4. Если вы когда-то сами загружали мод в Workshop, перенесите `Zomboid/Workshop/CoopQoL`
   за пределы папки `Zomboid`: игра читает моды и оттуда.
5. На своём или выделенном сервере очистите строку `WorkshopItems=` в
   `Zomboid/Server/<имя>.ini` (`Mods=CO-OP` оставьте).
6. Установите мод, как описано выше.

Мир не пострадает: отметки книг, список дел и всё остальное хранятся в сохранении, а не
в папке мода, а идентификатор мода не изменился.

Чтобы проверить, какую копию загрузила игра, откройте `Zomboid/console.txt`, когда
появится главное меню: строки `[CO-OP] ...` перечисляют запустившиеся функции, а
`recipe info row installed` значит, что это текущая версия.

### Мультиплеер

Одинаковая папка нужна всем — мода нет в Workshop, сам он не скачается, и без него
игрок не зайдёт на сервер.

На своём сервере мод нужно включить ещё и **в настройках сервера**, а не только в
клиентском списке модов:

1. Главное меню → **СВОЙ СЕРВЕР** → **«Настройка...»**
2. Выберите настройки → **«Редактировать выбранные настройки»**
3. Слева откройте группу **«Моды»**
4. В строке *«Добавить установленный мод в список»* выберите **CO-OP**
5. Сохраните, вернитесь, **ЗАПУСТИТЬ**

Это запишет `Mods=CO-OP` в `Zomboid/Server/<имя>.ini` — этот файл можно править и
вручную. Для выделенного сервера: положите папку в `Zomboid/mods/` сервера, добавьте
`CO-OP` в строку `Mods=`, перезапустите.

### Настройки

Всё находится в песочнице (sandbox), на отдельной странице **CO-OP**: в одиночной игре —
на экране создания мира, на сервере — в **«Настройка...» → «Редактировать выбранные
настройки»**. Там есть выключатель для каждой возможности (выключенная возвращает
обычное поведение игры, а не половину мода), а также время жизни метки, задержка между
метками одного игрока, объявление меток и изменений списка дел в чате, скорость опыта
«Организации», предел длины списка дел, три скорости, с которыми можно толкать
машину, и время, за которое выкопанный участок берега снова даёт глину (вместе с опытом
и количеством глины).

Настройки читаются в момент использования, поэтому изменение на запущенном сервере
доходит до всех без перезахода. Контейнеры, которые «Организация» уже увеличила,
сохраняют свой размер, даже если потом её выключить.

### Как пользоваться

| Возможность | Как |
|---|---|
| Отметить книгу | ПКМ по книге → **Книги дома** → *Отметить: дома* |
| Отметить целую полку | ПКМ по полке или ящику в мире → *Отметить всё как «дома»* |
| Открыть список книг | **K** (меняется: Настройки → Управление, раздел *Books At Home*) |
| Делиться отметками карты | Откройте карту, оставьте флажок **MP** включённым |
| Поставить метку | **Средняя кнопка мыши** в мире или на открытой карте (меняется: Настройки → Управление, раздел *CO-OP*) |
| Открыть список дел | **[** (тот же раздел) |
| Куда складывать предметы | Выпадающий список под кнопкой **Создать** или под списками деталей в окне механики |
| Навык «Организация» | В панели навыков персонажа, в группе «Создание» |
| Толкать машину | Встаньте спереди или сзади → **V** → *Толкать*. **Esc**, чтобы отпустить |
| Копать глину | Возьмите лопату → ПКМ по земле в шаге от реки или озера → *Копать глину* |
| Выкопать колодец | Окно постройки → *Наружное* → *Колодец* |
| Записать аудиокнигу | ПКМ по компьютеру с питанием → *Компьютер* → *Записать аудиокнигу* |
| Выключить возможность | Настройки песочницы → **CO-OP** |

### Обновление

Выйдите из игры **на рабочий стол** - код мода читается при запуске игры, поэтому
вернуться в главное меню недостаточно - замените папку `CO-OP` новой и запустите игру
снова. На сервере перезапустите и сервер: он использует свою копию мода. Версия должна
быть одинаковой у всех игроков.

### Удаление

Удалите `Zomboid/mods/CO-OP`. Отметки книг и список дел хранятся в мире и просто
игнорируются без мода.

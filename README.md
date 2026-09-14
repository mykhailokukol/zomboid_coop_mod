# CO-OP — Project Zomboid mod (Build 42)

Co-op tools for a shared base: a shared checklist of skill books, magazines and VHS
tapes, map marks shared automatically, a choice of where crafted and removed items
land, and an Organization skill that makes containers hold more.

**[English](#english) · [Українська](#українська) · [Русский](#русский)**

---

## English

### What it does

- **Books at home** — a shared checklist of skill books, recipe magazines and
  skill-teaching VHS tapes. One player marks an item as "at home", everyone on the
  server sees it, with who marked it, when, and an optional note ("Rosewood, top shelf").
  Marked items get a **white check mark** in the inventory; read books keep the green one.
- **Shared map marks** — an **MP** tick box on the map drawing panel, on by default.
  Everything you draw is shared with all players the moment you place it.
- **Item output destination** — one setting for where new items go: your hands, your
  bags, a container next to you, or the ground. Applies to crafting and to parts you
  take off a vehicle.
- **Organization skill** — a skill from 0 to 10 replacing the Organized / Disorganized
  traits. It raises the capacity of containers you organise (permanently, for everyone)
  and how fast you move items. Trained by the weight you move through storage.

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

### Using it

| Feature | How |
|---|---|
| Mark a book | Right-click it → **Books at home** → *Mark as at home* |
| Open the checklist | **K** (rebindable under Options → Keybindings) |
| Share map marks | Open the map, keep the **MP** box ticked |
| Choose where items go | The drop-down under the **Craft** button, or under the part lists in the vehicle mechanics window |
| Organization skill | In the character skills panel, under Crafting |

### Updating

Replace the `CO-OP` folder with the new one and restart the game. On a server, restart
the server too — it runs its own copy of the mod.

### Uninstalling

Delete `Zomboid/mods/CO-OP`. Book marks live in the world save and are simply ignored
once the mod is gone.

---

## Українська

### Що це

- **Книги вдома** — спільний список книг навичок, журналів рецептів і касет, що вчать
  навичок. Один гравець позначає предмет як «вдома», і це бачать усі на сервері: хто
  позначив, коли, і необов'язкова нотатка («Роузвуд, верхня полиця»). Позначені
  предмети отримують **білу галочку** в інвентарі; прочитані книги залишають зелену.
- **Спільні позначки на карті** — прапорець **MP** на панелі малювання карти, увімкнений
  за замовчуванням. Усе, що ви малюєте, одразу бачать усі гравці.
- **Куди складати нові предмети** — одне налаштування: у руки, у сумки, у контейнер
  поруч або на землю. Діє і для крафту, і для знятих з машини деталей.
- **Навичка «Організація»** — навичка від 0 до 10, що замінює риси «Організований» /
  «Неорганізований». Збільшує місткість контейнерів, які ви впорядковуєте (назавжди, для
  всіх), і швидкість перекладання речей. Зростає від ваги, яку ви переносите крізь
  сховища.

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

### Як користуватися

| Можливість | Як |
|---|---|
| Позначити книгу | ПКМ по книзі → **Книги вдома** → *Позначити: вдома* |
| Відкрити список | **K** (клавішу можна змінити: Налаштування → Керування) |
| Ділитися позначками карти | Відкрийте карту, залиште прапорець **MP** увімкненим |
| Куди складати предмети | Випадний список під кнопкою **Створити** або під списками деталей у вікні механіки |
| Навичка «Організація» | У панелі навичок персонажа, у групі «Створення» |

### Оновлення

Замініть теку `CO-OP` новою і перезапустіть гру. На сервері перезапустіть і сервер — він
використовує власну копію мода.

### Видалення

Видаліть `Zomboid/mods/CO-OP`. Позначки книг зберігаються у світі та просто
ігноруються без мода.

---

## Русский

### Что это

- **Книги дома** — общий список книг навыков, журналов рецептов и кассет, обучающих
  навыкам. Один игрок отмечает предмет как «дома», и это видят все на сервере: кто
  отметил, когда, и необязательная заметка («Роузвуд, верхняя полка»). Отмеченные
  предметы получают **белую галочку** в инвентаре; прочитанные книги сохраняют зелёную.
- **Общие отметки на карте** — флажок **MP** на панели рисования карты, включён по
  умолчанию. Всё, что вы рисуете, сразу видят все игроки.
- **Куда складывать новые предметы** — одна настройка: в руки, в сумки, в контейнер
  рядом или на землю. Работает и для крафта, и для снятых с машины деталей.
- **Навык «Организация»** — навык от 0 до 10, заменяющий черты «Организованный» /
  «Неорганизованный». Увеличивает вместимость контейнеров, которые вы разбираете
  (навсегда, для всех), и скорость перекладывания вещей. Растёт от веса, который вы
  переносите через хранилища.

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

### Как пользоваться

| Возможность | Как |
|---|---|
| Отметить книгу | ПКМ по книге → **Книги дома** → *Отметить: дома* |
| Открыть список | **K** (клавишу можно изменить: Настройки → Управление) |
| Делиться отметками карты | Откройте карту, оставьте флажок **MP** включённым |
| Куда складывать предметы | Выпадающий список под кнопкой **Создать** или под списками деталей в окне механики |
| Навык «Организация» | В панели навыков персонажа, в группе «Создание» |

### Обновление

Замените папку `CO-OP` новой и перезапустите игру. На сервере перезапустите и сервер —
он использует свою копию мода.

### Удаление

Удалите `Zomboid/mods/CO-OP`. Отметки книг хранятся в мире и просто игнорируются без
мода.

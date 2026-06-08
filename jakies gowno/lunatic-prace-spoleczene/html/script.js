/* ═══════════════════════════════════════════════════════════
   LUNATIC PRACE SPOLECZNE — UI + MINI-GRY
   ═══════════════════════════════════════════════════════════ */

const RES = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'lunatic-prace-spoleczne';
const $ = (id) => document.getElementById(id);

const root = $('root');
const state = {
    open: false,
    data: null,
    cooldownTimer: null,
    activeGame: null, // 'memory' | 'reaction' | 'anagram' | 'lockpick'
    activeGameTimer: null,
    activeGameStart: 0,
    // Buyout
    buyoutAmount: 1,
    buyoutBase: 100,
    buyoutCurve: 0.15,
    buyoutMax: 10,
    coinsBalance: 0,
};

function nui(endpoint, payload = {}) {
    return fetch(`https://${RES}/${endpoint}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(payload),
    }).then(r => r.json()).catch(() => ({}));
}

/* ───── OPEN / CLOSE ───── */

function show()   { root.classList.remove('hidden'); state.open = true; }
function hide()   { root.classList.add('hidden');    state.open = false; }

function applyData(data) {
    state.data = data;

    $('pointsBig').textContent = data.points || 0;
    $('completedNum').textContent = data.total_completed || 0;
    $('totalNum').textContent = (data.total_received) || 0;

    const pct = (data.total_received > 0)
        ? Math.min(100, ((data.total_completed || 0) / data.total_received) * 100)
        : 0;
    $('progressFill').style.width = pct + '%';

    $('assignedBy').textContent = data.assigned_by || '—';
    $('reasonText').textContent = data.reason || '—';

    $('streakNum').textContent = data.streak || 0;
    $('streakReq').textContent = data.streak_required || 5;

    $('killProgress').textContent = data.kill_progress || 0;
    $('killGoal').textContent = data.kills_per_point || 5;
    const kpct = (data.kills_per_point > 0)
        ? Math.min(100, ((data.kill_progress || 0) / data.kills_per_point) * 100)
        : 0;
    $('killBarFill').style.width = kpct + '%';

    $('duelReward').textContent = data.duel_reward || 2;

    // Multi-buyout: zachowaj ustawienia w state, przelicz cene
    if (typeof data.buyout_base === 'number') state.buyoutBase = data.buyout_base;
    if (typeof data.buyout_curve === 'number') state.buyoutCurve = data.buyout_curve;
    if (typeof data.buyout_max === 'number') state.buyoutMax = data.buyout_max;
    if (typeof data.coins_balance === 'number') state.coinsBalance = data.coins_balance;
    // Cap amount do mozliwych pkt
    state.buyoutAmount = Math.max(1, Math.min(state.buyoutAmount || 1,
        Math.min(data.points || 1, state.buyoutMax || 10)));
    refreshBuyoutUI(data.points || 0);

    if (data.buyout_enabled === false) {
        $('buyoutRow').style.display = 'none';
    } else {
        $('buyoutRow').style.display = '';  // pokaz domyslnie (chyba ze jawnie false)
    }

    // Cooldowny
    setupCooldown(data.cooldowns?.minigame || 0);
    $('buyoutBtn').disabled = (data.cooldowns?.buyout || 0) > 0;
}

/* ───── BUYOUT helpers ───── */

function calcBuyoutPrice(amount) {
    const base  = state.buyoutBase  ?? 100;
    const curve = state.buyoutCurve ?? 0.15;
    if (amount <= 0) return 0;
    return Math.floor(base * amount * (1 + (amount - 1) * curve));
}

function refreshBuyoutUI(maxPoints) {
    const max = Math.min(state.buyoutMax || 10, maxPoints || 1);
    const amount = Math.max(1, Math.min(state.buyoutAmount || 1, max));
    state.buyoutAmount = amount;

    $('buyoutAmount').textContent = amount;
    const price = calcBuyoutPrice(amount);
    $('buyoutPrice').textContent = price.toLocaleString('pl-PL');
    $('coinsBalance').textContent = (state.coinsBalance || 0).toLocaleString('pl-PL');

    // Stylizuj cene gdy nie stac
    const costEl = $('buyoutPrice');
    if (costEl) {
        if ((state.coinsBalance || 0) < price) costEl.classList.add('unaffordable');
        else costEl.classList.remove('unaffordable');
    }

    // Zablokuj +/− gdy na granicy
    const minus = $('buyoutMinus');
    const plus  = $('buyoutPlus');
    if (minus) minus.disabled = (amount <= 1);
    if (plus)  plus.disabled  = (amount >= max);
}

/* ───── COOLDOWN ───── */

function setupCooldown(seconds) {
    if (state.cooldownTimer) {
        clearInterval(state.cooldownTimer);
        state.cooldownTimer = null;
    }
    const pill = $('cooldownPill');
    const text = $('cooldownText');

    function tick() {
        if (seconds <= 0) {
            pill.classList.remove('active');
            text.textContent = 'Gotowe';
            document.querySelectorAll('.game-card').forEach(c => c.classList.remove('disabled'));
            clearInterval(state.cooldownTimer);
            state.cooldownTimer = null;
            return;
        }
        pill.classList.add('active');
        text.textContent = `Cooldown ${seconds}s`;
        document.querySelectorAll('.game-card').forEach(c => c.classList.add('disabled'));
        seconds--;
    }
    tick();
    if (seconds > 0) state.cooldownTimer = setInterval(tick, 1000);
}

/* ───── EVENTS — KOMUNIKACJA Z LUA ───── */

window.addEventListener('message', (e) => {
    const m = e.data;
    if (!m || !m.action) return;

    if (m.action === 'open') {
        applyData(m.data);
        show();
    } else if (m.action === 'close') {
        closeAllOverlays();
        hide();
    } else if (m.action === 'update') {
        applyData(m.data);
    } else if (m.action === 'cleared') {
        showCompletion();
    }
});

document.addEventListener('keydown', (e) => {
    if (!state.open) return;
    if (e.key === 'Escape') {
        if (state.activeGame) { closeMiniGame(true); }
        else { nui('close'); }
    }
});

/* ───── BUTTONS ───── */

$('closeBtn').addEventListener('click', () => nui('close'));

$('buyoutBtn').addEventListener('click', async () => {
    const amount = state.buyoutAmount || 1;
    const price  = calcBuyoutPrice(amount);
    if ((state.coinsBalance || 0) < price) {
        toast('fail', `Za malo coinow. Masz: ${state.coinsBalance || 0}, potrzeba: ${price}.`);
        return;
    }
    $('buyoutBtn').disabled = true;
    await nui('buyout', { amount });
    setTimeout(() => {
        nui('refresh').then(r => { if (r.data) applyData(r.data); });
    }, 600);
});

// +/- ilosc punktow do wykupienia
$('buyoutMinus').addEventListener('click', () => {
    state.buyoutAmount = Math.max(1, (state.buyoutAmount || 1) - 1);
    refreshBuyoutUI((state.data && state.data.points) || 0);
});
$('buyoutPlus').addEventListener('click', () => {
    const max = Math.min(state.buyoutMax || 10, (state.data && state.data.points) || 1);
    state.buyoutAmount = Math.min(max, (state.buyoutAmount || 1) + 1);
    refreshBuyoutUI((state.data && state.data.points) || 0);
});

document.querySelectorAll('.game-card').forEach(card => {
    card.addEventListener('click', async () => {
        if (card.classList.contains('disabled')) return;
        const type = card.dataset.game;
        const res = await nui('startMinigame', { type });
        if (!res.ok) {
            const msgs = {
                cooldown:    'Cooldown – poczekaj jeszcze chwile.',
                no_points:   'Nie masz punktow do odrobienia.',
                invalid_game:'Nieznana mini-gra.',
            };
            toast('fail', msgs[res.reason] || 'Nie mozna rozpoczac mini-gry.');
            if (res.reason === 'cooldown' && res.secondsLeft) setupCooldown(res.secondsLeft);
            return;
        }
        startMiniGame(type, res.payload);
    });
});

$('gameCancelBtn').addEventListener('click', () => closeMiniGame(true));

const mmBtn = $('mmMenuBtn');
if (mmBtn) {
    mmBtn.addEventListener('click', () => {
        nui('openMmMenu');
    });
}

/* ───── TOAST ───── */

function toast(kind, text) {
    const t = $('toast');
    t.className = `toast ${kind}`;
    $('toastIcon').textContent = kind === 'win' ? '✓' : (kind === 'fail' ? '✕' : 'ℹ');
    $('toastText').textContent = text;
    t.classList.remove('hidden');
    setTimeout(() => t.classList.add('hidden'), 2800);
}

/* ───── COMPLETION ───── */

function showCompletion() {
    $('completion').classList.remove('hidden');
}

function closeAllOverlays() {
    $('completion').classList.add('hidden');
    $('toast').classList.add('hidden');
    $('gameOverlay').classList.add('hidden');
}

/* ═══════════════════════════════════════════════════════════
   MINI-GRA — SHELL (timer + zamykanie)
   ═══════════════════════════════════════════════════════════ */

function startMiniGame(type, payload) {
    state.activeGame = type;
    state.activeGameStart = Date.now();

    const titles = {
        memory:   'SEKWENCJA',
        reaction: 'REFLEKS',
        anagram:  'ANAGRAM',
        lockpick: 'WLAM',
    };
    $('gameShellTitle').textContent = titles[type] || 'MINI-GRA';
    $('gameOverlay').classList.remove('hidden');

    // timer
    const maxMs = ({
        memory: 60000, reaction: 30000, anagram: 90000, lockpick: 45000,
    })[type] || 45000;
    if (state.activeGameTimer) clearInterval(state.activeGameTimer);
    state.activeGameTimer = setInterval(() => {
        const left = Math.max(0, Math.ceil((maxMs - (Date.now() - state.activeGameStart)) / 1000));
        $('gameShellTimer').textContent = left + 's';
        if (left <= 0) {
            clearInterval(state.activeGameTimer);
            // klient zglosi pusty wynik = fail (server odrzuci)
            finishMiniGame({});
        }
    }, 200);

    const body = $('gameBody');
    body.innerHTML = '';

    if (type === 'memory')   buildMemoryGame(body, payload);
    else if (type === 'reaction') buildReactionGame(body, payload);
    else if (type === 'anagram')  buildAnagramGame(body, payload);
    else if (type === 'lockpick') buildLockpickGame(body, payload);
}

async function finishMiniGame(result) {
    if (state.activeGameTimer) {
        clearInterval(state.activeGameTimer);
        state.activeGameTimer = null;
    }
    const r = await nui('endMinigame', result);
    if (r && r.ok) {
        toast('win', `Sukces! Zdjeto ${r.removed || 1} pkt${r.streakBonus ? ' (BONUS PASSY!)' : ''}`);
    } else {
        const msgs = {
            too_fast:   'Wykryto podejrzane tempo.',
            too_slow:   'Czas minal.',
            no_session: 'Sesja wygasla.',
            failed:     'Niepoprawnie wykonane.',
        };
        toast('fail', (r && msgs[r.reason]) || 'Nie udalo sie.');
    }
    closeMiniGame(false);
    setTimeout(() => nui('refresh').then(x => { if (x.data) applyData(x.data); }), 250);
}

function closeMiniGame(notify) {
    state.activeGame = null;
    if (state.activeGameTimer) {
        clearInterval(state.activeGameTimer);
        state.activeGameTimer = null;
    }
    $('gameOverlay').classList.add('hidden');
    $('gameBody').innerHTML = '';
    if (notify) nui('cancelMinigame');
}

/* ═══════════════════════════════════════════════════════════
   MEMORY — server-validated sequence
   ═══════════════════════════════════════════════════════════ */

function buildMemoryGame(root, payload) {
    const colors = ['#ff6b6b', '#4facfe', '#FF9F43', '#00d68f']; // 1=red,2=blue,3=orange,4=green
    const sequence = payload.sequence || [];
    let userInput = [];
    let phase = 'show'; // show -> input

    const wrap = document.createElement('div');
    wrap.className = 'mem-wrap';
    wrap.innerHTML = `
        <div class="mem-status show" id="memStatus">ZAPAMIETAJ SEKWENCJE</div>
        <div class="mem-board" id="memBoard">
            ${[1,2,3,4].map(i => `<div class="mem-cell" data-c="${i}" style="--col:${colors[i-1]}"></div>`).join('')}
        </div>
        <div class="mem-progress" id="memProgress">
            ${sequence.map(() => '<div class="mem-progress-dot"></div>').join('')}
        </div>
    `;
    root.appendChild(wrap);

    const cells = root.querySelectorAll('.mem-cell');
    const status = root.querySelector('#memStatus');
    const dots = root.querySelectorAll('.mem-progress-dot');

    function flashCell(idx) {
        return new Promise(res => {
            const cell = root.querySelector(`.mem-cell[data-c="${idx}"]`);
            cell.classList.add('lit');
            setTimeout(() => { cell.classList.remove('lit'); res(); }, 450);
        });
    }

    async function playSequence() {
        // Krotka pauza zeby gracz zauwazyl ze "zaczyna sie"
        await new Promise(r => setTimeout(r, 700));
        for (const v of sequence) {
            await flashCell(v);
            await new Promise(r => setTimeout(r, 200));
        }
        phase = 'input';
        status.className = 'mem-status input';
        status.textContent = 'POWTORZ KOLEJNOSC';
    }

    cells.forEach(cell => {
        cell.addEventListener('click', () => {
            if (phase !== 'input') return;
            cell.classList.add('flash');
            setTimeout(() => cell.classList.remove('flash'), 380);
            const c = parseInt(cell.dataset.c, 10);
            userInput.push(c);

            // sprawdz czy poprawne na biezaco
            const idx = userInput.length - 1;
            const expected = sequence[idx];
            if (c !== expected) {
                // zle — zglos pusto
                phase = 'done';
                status.textContent = 'BLAD!';
                status.style.color = 'var(--red)';
                setTimeout(() => finishMiniGame({ sequence: userInput }), 600);
                return;
            }
            dots[idx].classList.add('done');

            if (userInput.length === sequence.length) {
                phase = 'done';
                status.textContent = 'WYSYLAM...';
                setTimeout(() => finishMiniGame({ sequence: userInput }), 400);
            }
        });
    });

    playSequence();
}

/* ═══════════════════════════════════════════════════════════
   REACTION — kliknij N celow
   ═══════════════════════════════════════════════════════════ */

function buildReactionGame(root, payload) {
    const target = payload.targetsToHit || 12;
    let hits = 0;
    let misses = 0;

    const wrap = document.createElement('div');
    wrap.style.width = '100%';
    wrap.innerHTML = `
        <div class="react-area" id="reactArea">
            <div class="react-stats">
                <div class="react-stat">
                    <div class="react-stat-label">CELE</div>
                    <div class="react-stat-value" id="reactHits">0 / ${target}</div>
                </div>
                <div class="react-stat">
                    <div class="react-stat-label">PUDLA</div>
                    <div class="react-stat-value" id="reactMisses">0</div>
                </div>
            </div>
        </div>
    `;
    root.appendChild(wrap);
    const area = root.querySelector('#reactArea');

    let alive = true;

    area.addEventListener('click', (e) => {
        // klikniecie poza cel = pudlo
        if (e.target === area || e.target.classList.contains('react-stats') || e.target.classList.contains('react-stat')) {
            misses++;
            $('reactMisses').textContent = misses;
        }
    });

    function spawnTarget() {
        if (!alive) return;
        if (hits >= target) {
            alive = false;
            finishMiniGame({ hits });
            return;
        }
        const t = document.createElement('div');
        t.className = 'react-target';
        const rect = area.getBoundingClientRect();
        const padding = 30;
        t.style.left = (Math.random() * (rect.width - 56 - padding * 2) + padding) + 'px';
        t.style.top  = (Math.random() * (rect.height - 56 - padding * 2) + padding) + 'px';

        // limit zycia: 1.4s -> jezeli nie kliknal, zniknij i zlicz pudlo
        const liveTimer = setTimeout(() => {
            if (t.parentNode) {
                t.remove();
                misses++;
                $('reactMisses').textContent = misses;
                spawnTarget();
            }
        }, 1400);

        t.addEventListener('click', (ev) => {
            ev.stopPropagation();
            clearTimeout(liveTimer);
            t.classList.add('hit');
            hits++;
            $('reactHits').textContent = `${hits} / ${target}`;
            setTimeout(() => t.remove(), 280);
            // nastepny cel po krotkim opoznieniu
            setTimeout(spawnTarget, 250 + Math.random() * 200);
        });

        area.appendChild(t);
    }

    // start po ~600ms zeby spelnic minTimeMs (server: 5000ms minimum) — i tak ostatni klik bedzie pozniej
    setTimeout(spawnTarget, 600);

    // funkcja czyszczenia (gdy zamykamy)
    state._reactCleanup = () => { alive = false; };
}

/* ═══════════════════════════════════════════════════════════
   ANAGRAM — przeciagnij litery
   ═══════════════════════════════════════════════════════════ */

function buildAnagramGame(root, payload) {
    const scrambled = (payload.scrambled || '').split('');
    const wordLen = payload.wordLength || scrambled.length;
    let answer = []; // tablica { letter, srcIdx }

    const wrap = document.createElement('div');
    wrap.className = 'anag-wrap';
    wrap.innerHTML = `
        <div class="anag-answer" id="anagAnswer">
            ${Array.from({ length: wordLen }).map(() => '<div class="anag-slot"></div>').join('')}
        </div>
        <div class="anag-scrambled" id="anagScrambled">
            ${scrambled.map((l, i) => `<div class="anag-letter" data-i="${i}">${l}</div>`).join('')}
        </div>
        <div class="anag-actions">
            <button class="anag-btn" id="anagClear">WYCZYSC</button>
            <button class="anag-btn primary" id="anagSubmit">SPRAWDZ</button>
        </div>
    `;
    root.appendChild(wrap);

    const slots = root.querySelectorAll('#anagAnswer .anag-slot');
    const letters = root.querySelectorAll('#anagScrambled .anag-letter');

    function render() {
        slots.forEach((slot, i) => {
            const a = answer[i];
            if (a) {
                slot.classList.add('filled');
                slot.textContent = a.letter;
                slot.dataset.srcIdx = a.srcIdx;
            } else {
                slot.classList.remove('filled');
                slot.textContent = '';
                delete slot.dataset.srcIdx;
            }
        });
        letters.forEach((l, i) => {
            const used = answer.some(a => a.srcIdx === i);
            l.classList.toggle('used', used);
        });
    }

    letters.forEach(l => {
        l.addEventListener('click', () => {
            const idx = parseInt(l.dataset.i, 10);
            if (answer.some(a => a.srcIdx === idx)) return;
            if (answer.length >= wordLen) return;
            answer.push({ letter: l.textContent, srcIdx: idx });
            render();
        });
    });

    slots.forEach((slot, i) => {
        slot.addEventListener('click', () => {
            if (!answer[i]) return;
            answer.splice(i, 1);
            render();
        });
    });

    root.querySelector('#anagClear').addEventListener('click', () => {
        answer = []; render();
    });

    root.querySelector('#anagSubmit').addEventListener('click', () => {
        if (answer.length !== wordLen) {
            toast('fail', `Uzyj wszystkich ${wordLen} liter.`);
            return;
        }
        const word = answer.map(a => a.letter).join('');
        finishMiniGame({ answer: word });
    });
}

/* ═══════════════════════════════════════════════════════════
   LOCKPICK — trafiaj w ruchomy pasek
   ═══════════════════════════════════════════════════════════ */

function buildLockpickGame(root, payload) {
    const totalRounds = payload.rounds || 5;
    let round       = 0;
    let successes   = 0;
    let cursorPos   = 0;
    let dir         = 1;
    let speed       = 0.9;
    let zoneStart   = 35;
    let zoneSize    = 30;
    let canAttempt  = false;  // czy gracz moze teraz kliknac
    let running     = true;   // czy raf loop ma chodzic
    let raf         = null;
    let resolved    = false;  // czy gra zakonczona

    const wrap = document.createElement('div');
    wrap.className = 'lock-wrap';
    wrap.innerHTML = `
        <div class="lock-info">
            RUNDA <span id="lockRound">1</span> / ${totalRounds}
        </div>
        <div class="lock-bar" id="lockBar">
            <div class="lock-zone" id="lockZone"></div>
            <div class="lock-cursor" id="lockCursor"></div>
        </div>
        <div class="lock-rounds" id="lockRounds">
            ${Array.from({ length: totalRounds }).map(() => '<div class="lock-round"></div>').join('')}
        </div>
        <button class="lock-action" id="lockBtn">TRAFIAJ [SPACE]</button>
    `;
    root.appendChild(wrap);

    const cursorEl = root.querySelector('#lockCursor');
    const zoneEl   = root.querySelector('#lockZone');
    const btn      = root.querySelector('#lockBtn');
    const roundEls = root.querySelectorAll('.lock-rounds .lock-round');
    const roundLbl = root.querySelector('#lockRound');

    function placeZone() {
        // 14-22% szerokosci, randomowa pozycja (nie skraje)
        zoneSize  = 14 + Math.random() * 8;
        zoneStart = 5 + Math.random() * (90 - zoneSize);
        zoneEl.style.left  = zoneStart + '%';
        zoneEl.style.width = zoneSize + '%';
    }

    function startRound() {
        round++;
        if (round > totalRounds) {
            running = false;
            cancelAnimationFrame(raf);
            if (!resolved) {
                resolved = true;
                finishMiniGame({ successes });
            }
            return;
        }
        roundLbl.textContent = round;
        speed     = 0.9 + (round * 0.18);
        cursorPos = 0;
        dir       = 1;
        placeZone();
        canAttempt = true;
    }

    function loop() {
        if (!running) return;
        // Cursor zawsze sie porusza, niezaleznie od canAttempt
        cursorPos += dir * speed;
        if (cursorPos >= 100) { cursorPos = 100; dir = -1; }
        if (cursorPos <= 0)   { cursorPos = 0;   dir = 1; }
        cursorEl.style.left = cursorPos + '%';
        raf = requestAnimationFrame(loop);
    }

    function attempt() {
        if (!canAttempt || !running || resolved) return;
        canAttempt = false; // jedna proba na runde

        const inZone = (cursorPos >= zoneStart && cursorPos <= zoneStart + zoneSize);
        roundEls[round - 1].classList.add(inZone ? 'hit' : 'miss');
        if (inZone) successes++;

        // Po 350ms zacznij nastepna runde — cursor nie przestaje jezdzic w tym czasie
        setTimeout(() => {
            if (running && !resolved) startRound();
        }, 350);
    }

    btn.addEventListener('click', attempt);

    function onKey(e) {
        if (e.code === 'Space' || e.code === 'Enter') {
            e.preventDefault();
            attempt();
        }
    }
    document.addEventListener('keydown', onKey);

    // startuj pierwsza runde + loop
    startRound();
    loop();

    // cleanup gdyby zamknieto przed koncem
    state._lockpickCleanup = () => {
        running = false;
        canAttempt = false;
        cancelAnimationFrame(raf);
        document.removeEventListener('keydown', onKey);
    };
}

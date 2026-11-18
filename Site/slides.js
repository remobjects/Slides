const slide = document.querySelector('#slide');
const status = document.querySelector('#status');
const position = document.querySelector('#position');
const previous = document.querySelector('#previous');
const next = document.querySelector('#next');
const present = document.querySelector('#present');
const overview = document.querySelector('#overview');
const presenter = new URLSearchParams(location.search).get('presentation') !== '1';
const sync = new BroadcastChannel('esp-slides');
const deckQuery = presenter ? '?presenter=1' : '';
let deck;
let current = 1;
let step = 0;
let renderStep;
let displayedPage;
let synchronizedPosition;
let mermaid;
let timers;

async function request(query = '') {
  const response = await fetch('deck' + query, { cache: 'no-store' });
  if (!response.ok) throw new Error('Could not load the deck. Check the Markdown file and save again.');
  return response;
}

async function drawDiagrams(container) {
  const diagrams = container.querySelectorAll('.elements-markdown-mermaid');
  if (!diagrams.length) return;
  mermaid ??= new Promise((resolve, reject) => {
    const script = document.createElement('script');
    script.src = 'deck?asset=mermaid';
    script.onload = () => {
      window.mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', flowchart: { htmlLabels: false } });
      resolve(window.mermaid);
    };
    script.onerror = reject;
    document.head.append(script);
  });

  for (const diagram of diagrams) {
    try {
      const renderer = await mermaid;
      if (!diagram.isConnected) continue;
      const { svg } = await renderer.render('diagram-' + crypto.randomUUID(), diagram.textContent);
      if (!diagram.isConnected) continue;
      const figure = document.createElement('figure');
      figure.className = 'diagram';
      figure.innerHTML = svg;
      diagram.replaceWith(figure);
    } catch {
      diagram.title = 'Mermaid could not render this diagram';
    }
  }
}

function codeRanges(code, group) {
  if (group === '*') return '';
  const lineCount = code.textContent.replace(/\n$/, '').split('\n').length;
  const highlights = group.split(',').flatMap(range => {
    const [first, last = first] = range.trim().split('-').map(Number);
    const end = Math.min(last, lineCount);
    if (first < 1 || first > end) return [];
    const top = (first - 1) * 1.45;
    const height = (end - first + 1) * 1.45;
    return [`linear-gradient(#cad9f3, #cad9f3) 0 ${top}em / 100% ${height}em no-repeat`];
  });
  return highlights.join(', ');
}

function prepareCode(code) {
  const info = code.getAttribute('class')?.match(/^language-([\w#+.-]+)(?:\s+\{([\d,|* -]+)\})?$/);
  if (!info) return [];
  const [, language, ranges] = info;
  code.className = 'language-' + language;
  if (window.hljs?.getLanguage(language)) window.hljs.highlightElement(code);
  return ranges?.split('|').map(group => codeRanges(code, group.trim())) ?? [];
}

function renderSlide(container, page) {
  container.innerHTML = page?.html ?? '';
  container.dataset.layout = page?.layout ?? 'default';
  container.dataset.theme = page?.theme ?? '';
  container.scrollTop = 0;

  const frame = container.parentElement;
  frame.querySelector('.slide-logo')?.remove();
  if (page?.logo) {
    const logo = document.createElement('img');
    logo.className = 'slide-logo';
    logo.src = page.logo;
    logo.alt = '';
    frame.append(logo);
  }

  for (const group of container.querySelectorAll('[data-reveal="list"]')) {
    for (const item of group.querySelectorAll(':scope > :is(ul, ol) > li')) {
      item.dataset.reveal = 'click';
    }
  }

  const updates = [];
  let lastStep = 0;
  for (const element of container.querySelectorAll('[data-reveal="click"], [data-reveal="after"], pre > code')) {
    if (element.dataset.reveal) {
      if (element.dataset.reveal === 'click') lastStep += 1;
      const revealAt = lastStep;
      updates.push(value => {
        element.classList.toggle('unrevealed', value < revealAt);
        element.inert = value < revealAt;
      });
    } else {
      const ranges = prepareCode(element);
      if (!ranges.length) continue;
      const start = lastStep;
      lastStep += ranges.length - 1;
      updates.push(value => {
        const index = Math.min(value - start, ranges.length - 1);
        element.style.background = ranges[index] ?? '';
      });
    }
  }

  if (page) void drawDiagrams(container);
  return { lastStep, apply: value => updates.forEach(update => update(value)) };
}

function show(number, reveal = 0) {
  const count = deck?.slides.length ?? 0;
  const previousSlide = current;
  current = Math.max(1, Math.min(number, count));
  const page = deck?.slides[current - 1];
  const changedSlide = page && (!displayedPage || previousSlide !== current);
  if (!renderStep || page !== displayedPage) {
    displayedPage = page;
    renderStep = renderSlide(slide, page);
    if (presenter) {
      const upcoming = deck?.slides[current];
      document.querySelector('#notes').innerHTML = page?.notes ?? '';
      const nextPreview = document.querySelector('#upcoming');
      renderSlide(nextPreview, upcoming).apply(0);
      nextPreview.parentElement.hidden = !upcoming;
    }
  }
  step = Math.max(0, Math.min(reveal, renderStep.lastStep));
  renderStep.apply(step);
  if (timers) {
    if (changedSlide) timers.slide.reset();
    timers.update();
  }
  position.value = count ? `${current} / ${count}` : '';
  previous.disabled = current <= 1 && step === 0;
  next.disabled = current >= count && step >= renderStep.lastStep;
  if (count) history.replaceState(null, '', '#' + current + (step ? '.' + step : ''));
  const slideButtons = document.querySelectorAll('#slide-list button');
  slideButtons.forEach((button, index) => {
    if (index + 1 === current) button.setAttribute('aria-current', 'true');
    else button.removeAttribute('aria-current');
  });
}

function addressSlide() {
  const match = location.hash.match(/^#(\d+)(?:\.(\d+))?$/);
  return match ? [Number(match[1]), Number(match[2] ?? 0)] : [1, 0];
}

function navigate(number, reveal = 0) {
  show(number, reveal);
  if (deck?.slides.length) sync.postMessage({ position: [current, step] });
}

function advance(direction) {
  const reveal = step + direction;
  if (reveal >= 0 && reveal <= renderStep.lastStep) navigate(current, reveal);
  else if (direction > 0 && current < (deck?.slides.length ?? 0)) navigate(current + 1);
  else if (direction < 0 && current > 1) navigate(current - 1, Infinity);
}

function updateOverview() {
  const list = document.querySelector('#slide-list');
  const content = document.createElement('template');
  list.replaceChildren();
  deck.slides.forEach((page, index) => {
    content.innerHTML = page.html;
    const title = content.content.querySelector('h1, h2, h3')?.textContent;
    const item = document.createElement('li');
    const button = document.createElement('button');
    button.type = 'button';
    button.textContent = title || `Slide ${index + 1}`;
    button.addEventListener('click', () => {
      overview.close();
      navigate(index + 1);
    });
    item.append(button);
    list.append(item);
  });
}

async function refresh() {
  try {
    const revision = deck ? await (await request('?revision=1')).text() : null;
    if (!deck || revision !== deck.revision) {
      deck = await (await request(deckQuery)).json();
      document.title = deck.title + (presenter ? ' · Presenter' : ' · Presentation');
      updateOverview();
      show(...(synchronizedPosition ?? addressSlide()));
      synchronizedPosition = undefined;
    }
    status.textContent = deck.slides.length ? '' : 'Add a slide to the Markdown file and save.';
  } catch (error) {
    status.textContent = error.message;
  } finally {
    setTimeout(refresh, 1000);
  }
}

function openPresentation() {
  const output = window.open(`?presentation=1${location.hash}`,
    'esp-slides-presentation-' + location.port, 'popup,width=1280,height=720');
  output?.focus();
}

function openOverview() {
  if (!overview.open) {
    overview.showModal();
    overview.querySelector('[aria-current="true"]')?.focus();
  }
}

sync.addEventListener('message', ({ data }) => {
  if (data.requestPosition && deck?.slides.length) {
    sync.postMessage({ position: [current, step] });
  } else if (data.position) {
    if (deck) show(...data.position);
    else synchronizedPosition = data.position;
  }
});

function clockTime(seconds) {
  const minutes = Math.floor(seconds / 60);
  return minutes + ':' + String(seconds % 60).padStart(2, '0');
}

function createTimer(name, plannedDuration) {
  const panel = document.querySelector(`[data-timer="${name}"]`);
  const elapsed = panel.querySelector('.timer-elapsed');
  const remaining = panel.querySelector('.timer-remaining');
  let started = performance.now();

  function update(now) {
    const seconds = Math.floor((now - started) / 1000);
    elapsed.value = `${clockTime(seconds)} elapsed`;
    const planned = plannedDuration();
    remaining.hidden = !planned;
    if (!planned) return;

    const left = planned - seconds;
    const percent = Math.ceil(Math.max(0, left) / planned * 100);
    const time = left >= 0 ? `${clockTime(left)} left` : `${clockTime(-left)} over`;
    remaining.value = `${time} · ${percent}% remaining`;
    remaining.classList.toggle('over-time', left < 0);
  }

  function reset() {
    started = performance.now();
    update(started);
  }

  panel.querySelector('button').addEventListener('click', reset);
  return { update, reset };
}

function startTimers() {
  const presentationTimer = createTimer('deck', () => deck?.duration);
  const slideTimer = createTimer('slide', () => displayedPage?.duration);
  function update() {
    const now = performance.now();
    presentationTimer.update(now);
    slideTimer.update(now);
  }
  setInterval(update, 250);
  return { slide: slideTimer, update };
}

async function toggleFullscreen() {
  try {
    if (document.fullscreenElement) await document.exitFullscreen();
    else await document.documentElement.requestFullscreen();
  } catch {
    status.textContent = 'Fullscreen is unavailable in this browser.';
  }
}

previous.addEventListener('click', () => advance(-1));
next.addEventListener('click', () => advance(1));
present.addEventListener('click', openPresentation);
document.querySelector('#browse').addEventListener('click', openOverview);
document.body.classList.add(presenter ? 'presenter' : 'presentation');
if (presenter) {
  document.querySelector('nav').hidden = false;
  document.querySelector('#presenter-panel').hidden = false;
  timers = startTimers();
}
window.addEventListener('hashchange', () => navigate(...addressSlide()));
window.addEventListener('keydown', event => {
  if (overview.open || event.altKey || event.ctrlKey || event.metaKey || event.defaultPrevented) return;
  if (event.code === 'Space' && event.target.closest?.('button, a')) return;
  switch (event.key) {
    case 'ArrowRight':
    case 'PageDown':
      advance(1);
      break;
    case ' ':
      advance(event.shiftKey ? -1 : 1);
      break;
    case 'ArrowLeft':
    case 'PageUp':
      advance(-1);
      break;
    case 'Home':
      navigate(1);
      break;
    case 'End':
      navigate(deck?.slides.length ?? 1);
      break;
    case 'o':
    case 'O':
      if (!event.repeat && presenter) openOverview();
      break;
    case 'p':
    case 'P':
      if (!event.repeat && presenter) openPresentation();
      break;
    case 'f':
    case 'F':
      if (!event.repeat) void toggleFullscreen();
      break;
    default:
      return;
  }
  event.preventDefault();
});
show(...addressSlide());
if (!presenter || !location.hash) sync.postMessage({ requestPosition: true });
void refresh();

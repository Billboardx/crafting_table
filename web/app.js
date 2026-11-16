'use strict';
const $ = selector => document.querySelector(selector);
const app = $('#app');
const preview = !window.GetParentResourceName && new URLSearchParams(location.search).has('preview');
const iconBase = preview ? '../../skill_tree/web/vendor/fontawesome/css/' : 'https://cfx-nui-skill_tree/web/vendor/fontawesome/css/';
$('#icons-base').href = iconBase + 'fontawesome.min.css';
$('#icons-solid').href = iconBase + 'solid.min.css';
$('#icons-regular').href = iconBase + 'regular.min.css';
$('#icons-brands').href = iconBase + 'brands.min.css';
const escapeHtml = value => String(value ?? '').replace(/[&<>"']/g, char => ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' }[char]));
let state, categoryId, selectedId, pending = false, toastTimer, queueReceivedAt = 0;

function categoryIcon(value) {
  const icon = typeof value === 'string' ? value.trim() : '';
  if (!icon) return '<i class="fa-solid fa-screwdriver-wrench" aria-hidden="true"></i>';
  if (/^(?:(?:fa-solid|fa-regular|fa-brands|fas|far|fab)\s+)?(?:fa-)?[a-z0-9]+(?:-[a-z0-9]+)*$/.test(icon)) {
    const tokens = icon.split(/\s+/);
    const name = tokens.pop();
    return `<i class="${tokens[0] || 'fa-solid'} ${name.startsWith('fa-') ? name : 'fa-' + name}" aria-hidden="true"></i>`;
  }
  return escapeHtml(icon);
}
function toast(message, error = false) {
  if (!message) return;
  const element = $('#toast');
  element.textContent = message;
  element.classList.toggle('error', error);
  element.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { element.hidden = true; }, 4000);
}
function image(name, label) {
  const imageBase = preview ? '../../../%5Bqb%5D/qb-inventory/html/images/' : 'https://cfx-nui-qb-inventory/html/images/';
  return `<span class="item-art"><span class="fallback">◇</span>${name ? `<img src="${imageBase}${encodeURIComponent(name)}" alt="${escapeHtml(label)}">` : ''}</span>`;
}
app.addEventListener('load', event => {
  if (event.target.tagName === 'IMG') event.target.previousElementSibling.hidden = true;
}, true);
app.addEventListener('error', event => {
  if (event.target.tagName === 'IMG') event.target.remove();
}, true);
function receive(data) {
  state = data;
  queueReceivedAt = performance.now();
  if (!state.categories.some(category => category.id === categoryId)) categoryId = state.categories[0]?.id;
  if (!state.recipes.some(recipe => recipe.id === selectedId && recipe.category === categoryId)) {
    selectedId = state.recipes.find(recipe => recipe.category === categoryId)?.id;
  }
  render();
}
function setQueue(queue) {
  state.queue = queue;
  queueReceivedAt = performance.now();
  renderQueue();
}
function renderQueue() {
  const queue = state.queue || [];
  $('#queue-count').textContent = `${queue.length} / ${state.queueLimit}`;
  const count = state.collectionCount || 0;
  const collect = $('#collect');
  collect.textContent = `COLLECT ITEMS (${count})`;
  collect.disabled = pending || !count || queue.length > 0;
  $('#collect-hint').textContent = queue.length && count ? 'Collect when the queue finishes.' : '';
  if (!queue.length) {
    $('#queue').innerHTML = '<p class="queue-empty">No crafts in queue.</p>';
    return;
  }
  const label = escapeHtml(queue[0].label);
  const content = `<strong>${label}</strong><span class="queue-time"></span>`;
  $('#queue').innerHTML = `<div class="level-track queue-track" role="progressbar" aria-label="Crafting progress" aria-valuemin="0" aria-valuemax="100"><span class="level-fill"></span><div class="level-content">${content}</div><div class="level-content level-content-filled" aria-hidden="true">${content}</div></div>${queue.slice(1).map((job, index) => `<div class="queue-item"><span>${escapeHtml(job.label)}</span><span>#${index + 2}</span></div>`).join('')}`;
  updateQueueTimer();
}
function updateQueueTimer() {
  if (!state || app.hidden || !state.queue?.length) return;
  const job = state.queue[0];
  const remaining = Math.max(0, job.remaining - (performance.now() - queueReceivedAt));
  const progress = Math.min(100, Math.max(0, (1 - remaining / job.duration) * 100));
  const seconds = Math.ceil(remaining / 1000);
  const text = `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;
  const track = $('.queue-track');
  if (!track) return;
  track.style.setProperty('--level-progress', `${progress}%`);
  track.setAttribute('aria-valuenow', String(Math.floor(progress)));
  track.setAttribute('aria-valuetext', `${job.label}, ${text} remaining`);
  track.querySelectorAll('.queue-time').forEach(element => { element.textContent = text; });
}
setInterval(updateQueueTimer, 100);
function render() {
  const category = state.categories.find(item => item.id === categoryId);
  const recipes = state.recipes.filter(item => item.category === categoryId);
  const selected = recipes.find(item => item.id === selectedId);
  $('#station').textContent = state.station;
  $('#recipe-count').textContent = state.recipes.length;
  $('#level').textContent = state.level.level;
  $('#level-filled').textContent = state.level.level;
  const xpText = `${state.level.xp} / ${state.level.required} XP`;
  $('#level-xp').textContent = xpText;
  $('#level-xp-filled').textContent = xpText;
  const progress = $('.level-track');
  progress.setAttribute('aria-valuemax', String(state.level.required));
  progress.setAttribute('aria-valuenow', String(state.level.xp));
  progress.setAttribute('aria-valuetext', `Level ${state.level.level}, ${xpText}`);
  progress.style.setProperty('--level-progress', `${Math.min(100, Math.max(0, state.level.xp / state.level.required * 100))}%`);
  renderQueue();
  $('#categories').innerHTML = state.categories.map((item, index) => `<button data-category="${escapeHtml(item.id)}" class="category-card ${item.id === categoryId ? 'active' : ''}" aria-pressed="${item.id === categoryId}"><span class="category-art"><span class="category-symbol">${categoryIcon(item.icon)}</span><span class="category-index">${String(index + 1).padStart(2, '0')} / WORKSHOP</span></span><b>${escapeHtml(item.label)}</b><small>${state.recipes.filter(recipe => recipe.category === item.id).length} BLUEPRINTS</small></button>`).join('');
  $('#category-title').textContent = category?.label || 'Recipes';
  $('#category-subtitle').textContent = category?.subtitle || '';
  $('#recipes').innerHTML = recipes.length ? recipes.map((item, index) => {
    const configured = item.configured !== false;
    const ready = configured && item.ingredients.every(ingredient => ingredient.owned >= ingredient.amount);
    const status = !configured ? 'RECIPE UNAVAILABLE' : ready ? 'READY' : 'MATERIALS NEEDED';
    const info = configured ? `${item.ingredients.length} MATERIALS <span>·</span> ${Math.ceil(item.duration / 1000)} SEC` : 'RECIPE NOT CONFIGURED';
    return `<button class="recipe ${selectedId === item.id ? 'selected' : ''}" data-recipe="${escapeHtml(item.id)}" aria-pressed="${selectedId === item.id}"><span class="recipe-top"><span>BLUEPRINT / ${String(index + 1).padStart(2, '0')}</span><span class="recipe-status ${ready ? 'ready' : ''}">${status}</span></span>${image(item.image, '')}<span class="recipe-info"><b>${escapeHtml(item.label)}</b><small>${info}</small></span><span class="recipe-arrow">↗</span></button>`;
  }).join('') : '<div class="empty"><span class="empty-mark">?</span><b>No learned blueprints yet</b><p>Unlock a blueprint in the skill tree to see its item here.</p></div>';
  if (!selected) {
    $('#details').innerHTML = '<div class="detail-empty"><span class="empty-mark">?</span><h2>Select a recipe</h2><p>Learn a blueprint, then choose a recipe to view its materials.</p></div>';
    return;
  }
  const configured = selected.configured !== false;
  const canCraft = configured && selected.ingredients.every(item => item.owned >= item.amount);
  const recipeDetails = configured
    ? `<p class="detail-subtitle">Craft this item at the workstation.</p><div class="detail-stats"><span>OUTPUT <b>× ${selected.amount}</b></span><span>CRAFT TIME <b>${Math.ceil(selected.duration / 1000)} SEC</b></span><span>REWARD <b>+${selected.xp} XP</b></span></div><div class="materials-heading"><span>REQUIRED MATERIALS</span><span>OWNED / NEEDED</span></div><div class="materials">${selected.ingredients.map(item => `<div class="material">${image(item.image, '')}<span>${escapeHtml(item.label)}</span><b class="${item.owned < item.amount ? 'missing' : ''}">${item.owned} <i>/ ${item.amount}</i></b></div>`).join('')}</div>`
    : '<p class="detail-subtitle">This blueprint is unlocked, but no crafting recipe is available yet.</p>';
  const full = (state.queue || []).length >= state.queueLimit;
  const button = !configured ? 'RECIPE UNAVAILABLE' : full ? 'QUEUE FULL' : canCraft ? (state.queue?.length ? 'ADD TO QUEUE' : 'CRAFT ITEM') : 'NOT ENOUGH MATERIALS';
  $('#details').innerHTML = `<div class="detail-top"><span class="detail-badge">LEARNED BLUEPRINT</span><span class="detail-index">RECIPE DETAILS</span></div><div class="detail-art">${image(selected.image, selected.label)}</div><h2>${escapeHtml(selected.label)}</h2>${recipeDetails}<div class="detail-actions"><button id="craft" class="craft-button" ${pending || full || !canCraft ? 'disabled' : ''}>${button}</button>${configured ? '<p class="detail-hint">Return to this table to collect completed items.</p>' : ''}</div>`;
}
async function request(action, payload = {}) {
  if (pending) return;
  pending = true;
  if (state && !app.hidden) render();
  try {
    if (preview) { toast('Preview mode — connect to FiveM to perform this action.'); return; }
    const response = await fetch(`https://${GetParentResourceName()}/${action}`, { method:'POST', headers:{ 'Content-Type':'application/json' }, body:JSON.stringify(payload), signal:AbortSignal.timeout(12000) });
    if (!response.ok) throw new Error('NUI request failed');
    const result = await response.json();
    if (result.data) receive(result.data);
    if (action === 'craft' && result.ok && state) setQueue(result.queue);
    if (action === 'collect' && state && typeof result.collectionCount === 'number') state.collectionCount = result.collectionCount;
    toast(result.error || result.message, !result.ok);
  } catch {
    toast('Workshop connection unavailable. Please try again.', true);
  } finally {
    pending = false;
    if (state && !app.hidden) render();
  }
}
$('#categories').addEventListener('click', event => {
  const button = event.target.closest('[data-category]');
  if (!button) return;
  categoryId = button.dataset.category;
  selectedId = state.recipes.find(recipe => recipe.category === categoryId)?.id;
  render();
});
$('#recipes').addEventListener('click', event => {
  const button = event.target.closest('[data-recipe]');
  if (button) { selectedId = button.dataset.recipe; render(); }
});
$('#details').addEventListener('click', event => {
  const selected = state.recipes.find(item => item.id === selectedId);
  if (event.target.closest('#craft') && selected?.recipeId) request('craft', { id: selected.recipeId });
});
$('#close').addEventListener('click', () => request('close'));
$('#back').addEventListener('click', () => request('close'));
$('#skills').addEventListener('click', () => request('skills'));
$('#refresh').addEventListener('click', () => request('refresh'));
$('#collect').addEventListener('click', () => request('collect'));
document.addEventListener('keydown', event => { if (event.key === 'Escape' && !app.hidden) request('close'); });
window.addEventListener('message', event => {
  const message = event.data;
  if (message.action === 'open') { app.hidden = false; receive(message.data); }
  if (message.action === 'close') app.hidden = true;
  if (message.action === 'update' && !app.hidden) receive(message.data);
  if (message.action === 'level' && state && !app.hidden) { state.level = message.level; render(); }
  if (message.action === 'queue' && state && !app.hidden) { setQueue(message.queue); render(); }
  if (message.action === 'result' && !app.hidden) {
    toast(message.message, !message.ok);
    render();
  }
});
if (preview) {
  app.hidden = false;
  receive({ station:'Workshop', queue:[], queueLimit:5, collectionCount:0, level:{level:2, xp:45, required:125}, categories:[{ id:'essentials', label:'Essentials', subtitle:'Tools for everyday work', icon:'fa-solid fa-screwdriver-wrench' }, { id:'electronics', label:'Electronics', subtitle:'Connect. Build. Progress.', icon:'fa-solid fa-microchip' }, { id:'weapons', label:'Weapons', icon:'fa-solid fa-crosshairs' }], recipes:[
    { id:'lockpick', recipeId:'lockpick', category:'essentials', label:'Lockpick', image:'lockpick.png', amount:1, duration:5000, xp:15, ingredients:[{ label:'Metal Scrap', image:'metalscrap.png', owned:43, amount:22 }, { label:'Plastic', image:'plastic.png', owned:18, amount:32 }] },
    { id:'repairkit', recipeId:'repairkit', category:'essentials', label:'Repair Kit', image:'repairkit.png', amount:1, duration:8000, xp:25, ingredients:[{ label:'Metal Scrap', image:'metalscrap.png', owned:43, amount:32 }, { label:'Steel', image:'steel.png', owned:50, amount:43 }, { label:'Plastic', image:'plastic.png', owned:80, amount:61 }] },
    { id:'advancedlockpick', recipeId:'advancedlockpick', category:'essentials', label:'Advanced Lockpick', image:'advancedlockpick.png', amount:1, duration:8000, xp:25, ingredients:[{ label:'Metal Scrap', image:'metalscrap.png', owned:43, amount:30 }, { label:'Steel', image:'steel.png', owned:12, amount:20 }, { label:'Plastic', image:'plastic.png', owned:18, amount:20 }] },
    { id:'radio', recipeId:'radio', category:'electronics', label:'Radio', image:'radio.png', amount:1, duration:7000, xp:20, ingredients:[{ label:'Plastic', image:'plastic.png', owned:18, amount:25 }, { label:'Copper', image:'copper.png', owned:25, amount:20 }] },
    { id:'skill:weapon_pistol', configured:false, category:'weapons', label:'Pistol', image:'weapon_pistol.png' }
  ] });
}

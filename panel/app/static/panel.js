'use strict';

const language = document.getElementById('panel-language');
language?.addEventListener('change', () => language.form.requestSubmit());

for (const trigger of document.querySelectorAll('[data-open-dialog]')) {
  trigger.addEventListener('click', () => document.getElementById(trigger.dataset.openDialog).showModal());
}

for (const trigger of document.querySelectorAll('[data-close-dialog]')) {
  trigger.addEventListener('click', () => trigger.closest('dialog').close());
}

for (const form of document.querySelectorAll('form[data-confirm]')) {
  form.addEventListener('submit', (event) => {
    if (!window.confirm(form.dataset.confirm)) event.preventDefault();
  });
}

for (const trigger of document.querySelectorAll('[data-copy]')) {
  trigger.addEventListener('click', async () => {
    const field = document.getElementById(trigger.dataset.copy);
    const feedback = document.querySelector('.copy-feedback');
    try {
      await navigator.clipboard.writeText(field.value);
      feedback.textContent = trigger.dataset.copied;
    } catch (error) {
      field.focus();
      field.select();
      feedback.textContent = trigger.dataset.copyFallback;
    }
  });
}

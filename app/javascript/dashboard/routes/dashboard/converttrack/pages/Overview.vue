<script setup>
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const CONVERTTRACK_URL = 'http://127.0.0.1:5000';

const loading = ref(true);
const status = ref(null);
const error = ref('');

const fetchStatus = async () => {
  loading.value = true;
  error.value = '';
  try {
    const response = await fetch(`${CONVERTTRACK_URL}/api/dashboard`);
    status.value = await response.json();
  } catch (e) {
    error.value = t('CONVERTTRACK.OVERVIEW.ERROR');
  } finally {
    loading.value = false;
  }
};

onMounted(fetchStatus);
</script>

<template>
  <div class="flex flex-col flex-1 overflow-auto bg-n-slate-1 p-6">
    <div class="max-w-3xl mx-auto w-full space-y-6">
      <div>
        <h1 class="text-2xl font-semibold text-n-slate-12">
          {{ $t('CONVERTTRACK.OVERVIEW.TITLE') }}
        </h1>
        <p class="text-n-slate-11 mt-2">
          {{ $t('CONVERTTRACK.OVERVIEW.SUBTITLE') }}
        </p>
      </div>

      <div class="rounded-xl border border-n-slate-4 bg-n-slate-2 p-5 space-y-3">
        <h2 class="font-medium text-n-slate-12">
          {{ $t('CONVERTTRACK.OVERVIEW.STATUS_TITLE') }}
        </h2>
        <p v-if="loading" class="text-n-slate-11">
          {{ $t('CONVERTTRACK.OVERVIEW.LOADING') }}
        </p>
        <p v-else-if="error" class="text-ruby-11">{{ error }}</p>
        <div v-else-if="status" class="space-y-2 text-sm text-n-slate-11">
          <p>
            <span class="text-n-slate-12 font-medium">Service:</span>
            {{ status.service }} ({{ status.status }})
          </p>
          <p>
            <span class="text-n-slate-12 font-medium">Modele IA:</span>
            {{ status.model }}
          </p>
          <p>
            <span class="text-n-slate-12 font-medium">Webhook:</span>
            {{ status.webhook_url }}
          </p>
        </div>
      </div>

      <div class="rounded-xl border border-n-slate-4 bg-n-slate-2 p-5">
        <h2 class="font-medium text-n-slate-12 mb-3">
          {{ $t('CONVERTTRACK.OVERVIEW.FLOW_TITLE') }}
        </h2>
        <ol class="list-decimal list-inside space-y-2 text-sm text-n-slate-11">
          <li>{{ $t('CONVERTTRACK.OVERVIEW.FLOW_1') }}</li>
          <li>{{ $t('CONVERTTRACK.OVERVIEW.FLOW_2') }}</li>
          <li>{{ $t('CONVERTTRACK.OVERVIEW.FLOW_3') }}</li>
          <li>{{ $t('CONVERTTRACK.OVERVIEW.FLOW_4') }}</li>
        </ol>
      </div>
    </div>
  </div>
</template>

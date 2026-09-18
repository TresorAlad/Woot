<script setup>
const testUrl = 'http://127.0.0.1:5000/test';
</script>

<template>
  <div class="flex flex-col flex-1 bg-n-slate-1">
    <div class="px-6 py-4 border-b border-n-slate-4">
      <h1 class="text-xl font-semibold text-n-slate-12">
        {{ $t('CONVERTTRACK.TEST.TITLE') }}
      </h1>
      <p class="text-sm text-n-slate-11 mt-1">
        {{ $t('CONVERTTRACK.TEST.SUBTITLE') }}
      </p>
    </div>
    <iframe
      :src="testUrl"
      class="flex-1 w-full border-0 min-h-[70vh]"
      title="ConvertTrack test widget"
    />
  </div>
</template>

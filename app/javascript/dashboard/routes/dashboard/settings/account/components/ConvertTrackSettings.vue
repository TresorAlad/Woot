<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import SectionLayout from './SectionLayout.vue';
import WithLabel from 'v3/components/Form/WithLabel.vue';
import NextInput from 'next/input/Input.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const { currentAccount, updateAccount } = useAccount();

const automationMode = ref('classification');
const workspaceType = ref('custom');
const catalogSourcesText = ref('');
const isSaving = ref(false);

const automationModes = computed(() => [
  { value: 'classification', label: t('GENERAL_SETTINGS.FORM.CONVERTTRACK.AUTOMATION_MODES.CLASSIFICATION') },
  { value: 'agentic', label: t('GENERAL_SETTINGS.FORM.CONVERTTRACK.AUTOMATION_MODES.AGENTIC') },
  { value: 'hybrid', label: t('GENERAL_SETTINGS.FORM.CONVERTTRACK.AUTOMATION_MODES.HYBRID') },
]);

const workspaceTypes = computed(() => [
  { value: 'custom', label: t('GENERAL_SETTINGS.FORM.CONVERTTRACK.WORKSPACE_TYPES.CUSTOM') },
  { value: 'marketing', label: t('GENERAL_SETTINGS.FORM.CONVERTTRACK.WORKSPACE_TYPES.MARKETING') },
  { value: 'support', label: t('GENERAL_SETTINGS.FORM.CONVERTTRACK.WORKSPACE_TYPES.SUPPORT') },
  { value: 'reclamations', label: t('GENERAL_SETTINGS.FORM.CONVERTTRACK.WORKSPACE_TYPES.RECLAMATIONS') },
]);

watch(
  currentAccount,
  () => {
    const settings = currentAccount.value?.settings || {};
    automationMode.value = settings.converttrack_automation_mode || 'classification';
    workspaceType.value = settings.converttrack_workspace_type || 'custom';
    catalogSourcesText.value = Array(settings.converttrack_catalog_sources || []).join('\n');
  },
  { deep: true, immediate: true }
);

const saveSettings = async () => {
  isSaving.value = true;
  try {
    const catalogSources = catalogSourcesText.value
      .split('\n')
      .map(line => line.trim())
      .filter(Boolean);

    await updateAccount({
      converttrack_automation_mode: automationMode.value,
      converttrack_workspace_type: workspaceType.value,
      converttrack_catalog_sources: catalogSources,
    });
    useAlert(t('GENERAL_SETTINGS.FORM.CONVERTTRACK.API.SUCCESS'));
  } catch (error) {
    useAlert(t('GENERAL_SETTINGS.FORM.CONVERTTRACK.API.ERROR'));
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <SectionLayout
    :title="t('GENERAL_SETTINGS.FORM.CONVERTTRACK.TITLE')"
    :description="t('GENERAL_SETTINGS.FORM.CONVERTTRACK.NOTE')"
    with-border
  >
    <form class="grid gap-4" @submit.prevent="saveSettings">
      <WithLabel
        name="converttrack-workspace-type"
        :label="t('GENERAL_SETTINGS.FORM.CONVERTTRACK.WORKSPACE_TYPE.LABEL')"
      >
        <select v-model="workspaceType" class="!mb-0 text-sm">
          <option
            v-for="option in workspaceTypes"
            :key="option.value"
            :value="option.value"
          >
            {{ option.label }}
          </option>
        </select>
      </WithLabel>

      <WithLabel
        name="converttrack-automation-mode"
        :label="t('GENERAL_SETTINGS.FORM.CONVERTTRACK.AUTOMATION_MODE.LABEL')"
      >
        <select v-model="automationMode" class="!mb-0 text-sm">
          <option
            v-for="option in automationModes"
            :key="option.value"
            :value="option.value"
          >
            {{ option.label }}
          </option>
        </select>
        <template #help>
          {{ t('GENERAL_SETTINGS.FORM.CONVERTTRACK.AUTOMATION_MODE.HELP') }}
        </template>
      </WithLabel>

      <WithLabel
        name="converttrack-catalog-sources"
        :label="t('GENERAL_SETTINGS.FORM.CONVERTTRACK.CATALOG_SOURCES.LABEL')"
      >
        <textarea
          v-model="catalogSourcesText"
          rows="4"
          class="w-full text-sm"
          :placeholder="t('GENERAL_SETTINGS.FORM.CONVERTTRACK.CATALOG_SOURCES.PLACEHOLDER')"
        />
      </WithLabel>

      <div>
        <NextButton blue :is-loading="isSaving" type="submit">
          {{ t('GENERAL_SETTINGS.FORM.CONVERTTRACK.SUBMIT') }}
        </NextButton>
      </div>
    </form>
  </SectionLayout>
</template>

<script>
/* global axios */
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import {
  DuplicateContactException,
  ExceptionWithMessage,
} from 'shared/helpers/CustomErrors';
import { dynamicTime } from 'shared/helpers/timeHelper';
import { useAdmin } from 'dashboard/composables/useAdmin';
import ContactInfoRow from './ContactInfoRow.vue';
import Avatar from 'next/avatar/Avatar.vue';
import SocialIcons from './SocialIcons.vue';
import EditContact from './EditContact.vue';
import ContactMergeModal from 'dashboard/modules/contact/ContactMergeModal.vue';
import ContactDeleteModal from 'dashboard/modules/contact/ContactDeleteModal.vue';
import ComposeConversation from 'dashboard/components-next/NewConversation/ComposeConversation.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import VoiceCallButton from 'dashboard/components-next/Contacts/VoiceCallButton.vue';
import InlineInput from 'dashboard/components-next/inline-input/InlineInput.vue';

export default {
  components: {
    NextButton,
    ContactInfoRow,
    EditContact,
    Avatar,
    ComposeConversation,
    SocialIcons,
    ContactMergeModal,
    ContactDeleteModal,
    VoiceCallButton,
    InlineInput,
  },
  props: {
    contact: {
      type: Object,
      default: () => ({}),
    },
    showAvatar: {
      type: Boolean,
      default: true,
    },
  },
  emits: ['panelClose'],
  setup() {
    const { isAdmin } = useAdmin();
    return {
      isAdmin,
    };
  },
  data() {
    return {
      comment: '',
      odoos: [],
      agents: [],
      selectedOdoo: '',
      selectedAgent: '',
      sendedToOdoo: false,
      loadingOdoo: false,
      currentContactId: null,
      showEditModal: false,
      isEditingName: false,
      editName: '',
    };
  },
  computed: {
    ...mapGetters({
      uiFlags: 'contacts/getUIFlags',
      currentChat: 'getSelectedChat',
    }),
    contactProfileLink() {
      return `/app/accounts/${this.$route.params.accountId}/contacts/${this.contact.id}`;
    },
    additionalAttributes() {
      return this.contact.additional_attributes || {};
    },
    canSendOdoo() {
      return this.selectedOdoo && this.selectedAgent;
    },
    location() {
      const {
        country = '',
        city = '',
        country_code: countryCode,
      } = this.additionalAttributes;
      const cityAndCountry = [city, country].filter(item => !!item).join(', ');

      if (!cityAndCountry) {
        return '';
      }
      return this.findCountryFlag(countryCode, cityAndCountry);
    },
    socialProfiles() {
      const {
        social_profiles: socialProfiles,
        screen_name: twitterScreenName,
        social_telegram_user_name: telegramUsername,
      } = this.additionalAttributes;

      const telegram = socialProfiles?.telegram || telegramUsername || '';
      const twitter = socialProfiles?.twitter || twitterScreenName || '';

      return {
        ...(socialProfiles || {}),
        twitter,
        telegram,
      };
    },
  },
  watch: {
    'contact.id': {
      handler(id) {
        this.$store.dispatch('contacts/fetchContactableInbox', id);
      },
      immediate: true,
    },
  },
  methods: {
    dynamicTime,
    toggleEditModal() {
      this.showEditModal = !this.showEditModal;
    },
    findCountryFlag(countryCode, cityAndCountry) {
      try {
        if (!countryCode) {
          return `${cityAndCountry} 🌎`;
        }

        const code = countryCode?.toLowerCase();
        return `${cityAndCountry} <span class="fi fi-${code} size-3.5"></span>`;
      } catch (error) {
        return '';
      }
    },
    async deleteContact({ id }) {
      try {
        await this.$store.dispatch('contacts/delete', id);
        this.$emit('panelClose');
        useAlert(this.$t('DELETE_CONTACT.API.SUCCESS_MESSAGE'));

        if (isAConversationRoute(this.$route.name)) {
          this.$router.push({
            name: getConversationDashboardRoute(this.$route.name),
          });
        } else if (isAInboxViewRoute(this.$route.name)) {
          this.$router.push({
            name: 'inbox_view',
          });
        } else if (this.$route.name !== 'contacts_dashboard') {
          this.$router.push({
            name: 'contacts_dashboard',
          });
        }
      } catch (error) {
        useAlert(
          error.response?.data?.message
            ? error.response?.data?.message
            : this.$t('DELETE_CONTACT.API.ERROR_MESSAGE')
        );
      }
    },
    startEditingName() {
      this.editName = this.contact.name || '';
      this.isEditingName = true;
      this.$nextTick(() => {
        this.$refs.nameInput?.focus();
      });
    },
    saveNameEdit() {
      if (!this.isEditingName) return;
      this.isEditingName = false;
      const trimmed = this.editName.trim();
      if (trimmed && trimmed !== this.contact.name) {
        this.updateContactField({ name: trimmed });
      }
    },
    cancelNameEdit() {
      this.isEditingName = false;
    },
    onFieldUpdate(field, value) {
      this.updateContactField({ [field]: value });
    },
    async updateContactField(attrs) {
      const contactId = this.contact.id;
      try {
        await this.$store.dispatch('contacts/update', {
          id: contactId,
          ...attrs,
        });
        useAlert(this.$t('CONTACT_FORM.SUCCESS_MESSAGE'));
        await this.$store.dispatch('contacts/fetchContactableInbox', contactId);
      } catch (error) {
        if (error instanceof DuplicateContactException) {
          const detail = error.contactErrorDetail;
          if (detail) {
            useAlert(detail);
          } else {
            const invalidAttrs = Array.isArray(error.data) ? error.data : [];
            if (invalidAttrs.includes('email')) {
              useAlert(this.$t('CONTACT_FORM.FORM.EMAIL_ADDRESS.DUPLICATE'));
            } else if (invalidAttrs.includes('phone_number')) {
              useAlert(this.$t('CONTACT_FORM.FORM.PHONE_NUMBER.DUPLICATE'));
            } else {
              useAlert(this.$t('CONTACT_FORM.ERROR_MESSAGE'));
            }
          }
        } else if (error instanceof ExceptionWithMessage) {
          useAlert(error.data);
        } else {
          useAlert(error.message || this.$t('CONTACT_FORM.ERROR_MESSAGE'));
        }
      }
    },
    async loadOdooContact() {
      this.comment = '';
      this.sendedToOdoo = false;
      this.currentContactId = this.contact.id;
      this.loadingOdoo = true;
      try {
        this.selectedAgent = '';
        const { data } = await axios.get('/api/v1/odoo', {
          params: {
            list: 'odoo',
            account_id: this.$route.params.accountId,
            contact_id: this.contact.id,
          },
        });
        this.odoos = data;
      } catch (error) {
        this.sendedToOdoo = true;
      } finally {
        this.loadingOdoo = false;
      }
    },
    async changeOdooInstance() {
      this.selectedAgent = '';
      this.agents = [];
      this.getContactList(this.selectedOdoo);
    },
    async getContactList(odoo_id) {
      try {
        const { data } = await axios.get(`/api/v1/odoo`, {
          params: {
            list: 'contact',
            account_id: 1,
            odoo_id: odoo_id,
          },
        });
        this.agents = data.result;
      } catch (error) {
        useAlert(
          error.response?.data?.message
            ? error.response?.data?.message
            : this.$t('SEND_TO_ODOO.API.ERROR_MESSAGE')
        );
      }
    },
    async sendToOdoo() {
      try {
        if (this.selectedOdoo && this.selectedAgent) {
          await axios
            .post(`/api/v1/odoo`, {
              odoo_id: this.selectedOdoo,
              agent_id: this.selectedAgent,
              contact_id: this.contact.id,
              comment: this.comment,
            })
            .then(() => {
              this.sendedToOdoo = true;
              this.comment = '';
            });
          useAlert('Send to Odoo successfully');
        } else {
          useAlert('Please select an Odoo and Agent');
        }
      } catch (error) {
        useAlert(
          error.response?.data?.message
            ? error.response?.data?.message
            : this.$t('SEND_TO_ODOO.API.ERROR_MESSAGE')
        );
      }
    },
    async sendToOdoo2() {
      try {
        await axios.get(`/api/v1/odoo`, {
          params: {
            list: 'odoo',
            account_id: 1,
            contact_id: 10,
          },
        });
      } catch (error) {
        useAlert(
          error.response?.data?.message
            ? error.response?.data?.message
            : this.$t('SEND_TO_ODOO.API.ERROR_MESSAGE')
        );
      }
    },
  },
};
</script>

<template>
  <div class="relative items-center w-full p-4">
    <div class="flex flex-col w-full gap-2 text-left rtl:text-right">
      <div class="flex flex-row justify-between">
        <Avatar
          v-if="showAvatar"
          :src="contact.thumbnail"
          :name="contact.name"
          :status="contact.availability_status"
          :size="48"
          hide-offline-status
        />
      </div>

      <div class="flex flex-col items-start gap-1.5 min-w-0 w-full">
        <div v-if="showAvatar" class="flex items-center w-full min-w-0 gap-3">
          <InlineInput
            v-if="isEditingName"
            ref="nameInput"
            v-model="editName"
            custom-input-class="!text-base !font-medium"
            class="!w-fit"
            @enter-press="saveNameEdit"
            @escape-press="cancelNameEdit"
            @blur="saveNameEdit"
          />
          <h3
            v-else
            class="group/name flex-shrink max-w-full min-w-0 my-0 text-base capitalize break-words text-n-slate-12 cursor-pointer hover:text-n-slate-12/80"
            :title="$t('CONTACT_PANEL.CLICK_TO_EDIT')"
            @click="startEditingName"
          >
            {{ contact.name }}
            <span
              class="i-lucide-pencil text-xs text-n-slate-10 opacity-0 group-hover/name:opacity-100 transition-opacity ml-1 align-middle"
            />
          </h3>
          <div class="flex flex-row items-center gap-2">
            <span
              v-if="contact.created_at"
              v-tooltip.left="
                `${$t('CONTACT_PANEL.CREATED_AT_LABEL')} ${dynamicTime(
                  contact.created_at
                )}`
              "
              class="i-lucide-info text-sm text-n-slate-10"
            />
            <a
              :href="contactProfileLink"
              target="_blank"
              rel="noopener nofollow noreferrer"
              class="leading-3"
            >
              <span class="i-lucide-external-link text-sm text-n-slate-10" />
            </a>
          </div>
        </div>

        <p v-if="additionalAttributes.description" class="break-words mb-0.5">
          {{ additionalAttributes.description }}
        </p>
        <div class="flex flex-col items-start w-full gap-2">
          <ContactInfoRow
            :href="contact.email ? `mailto:${contact.email}` : ''"
            :value="contact.email"
            icon="mail"
            emoji="✉️"
            :title="$t('CONTACT_PANEL.EMAIL_ADDRESS')"
            show-copy
            editable
            @update="value => onFieldUpdate('email', value)"
          />
          <ContactInfoRow
            :href="contact.phone_number ? `tel:${contact.phone_number}` : ''"
            :value="contact.phone_number"
            icon="call"
            emoji="📞"
            :title="$t('CONTACT_PANEL.PHONE_NUMBER')"
            show-copy
            editable
            @update="value => onFieldUpdate('phone_number', value)"
          />
          <ContactInfoRow
            v-if="contact.identifier"
            :value="contact.identifier"
            icon="contact-identify"
            emoji="🪪"
            :title="$t('CONTACT_PANEL.IDENTIFIER')"
          />
          <ContactInfoRow
            :value="additionalAttributes.company_name"
            icon="building-bank"
            emoji="🏢"
            :title="$t('CONTACT_PANEL.COMPANY')"
            editable
            @update="
              value =>
                updateContactField({
                  additional_attributes: {
                    ...additionalAttributes,
                    company_name: value,
                  },
                })
            "
          />
          <ContactInfoRow
            v-if="location || additionalAttributes.location"
            :value="location || additionalAttributes.location"
            icon="map"
            emoji="🌍"
            :title="$t('CONTACT_PANEL.LOCATION')"
          />
          <SocialIcons :social-profiles="socialProfiles" />
        </div>
      </div>
      <div class="flex items-center w-full mt-0.5 gap-2">
        <ComposeConversation :contact-id="String(contact.id)">
          <template #trigger>
            <NextButton
              v-tooltip.top-end="$t('CONTACT_PANEL.NEW_MESSAGE')"
              icon="i-ph-chat-circle-dots"
              slate
              faded
              sm
            />
          </template>
        </ComposeConversation>
        <VoiceCallButton
          :phone="contact.phone_number"
          :contact-id="contact.id"
          :conversation-id="currentChat?.id"
          icon="i-lucide-phone"
          sm
          faded
          slate
          :tooltip-label="$t('CONTACT_PANEL.CALL')"
        />
        <NextButton
          v-tooltip.top-end="$t('EDIT_CONTACT.BUTTON_LABEL')"
          icon="i-ph-pencil-simple"
          slate
          faded
          sm
          @click="toggleEditModal"
        />
        <ContactMergeModal :primary-contact="contact">
          <template #trigger>
            <NextButton
              v-tooltip.top-end="$t('CONTACT_PANEL.MERGE_CONTACT')"
              icon="i-ph-arrows-merge"
              slate
              faded
              sm
              :disabled="uiFlags.isMerging"
            />
          </template>
        </ContactMergeModal>
        <ContactDeleteModal
          v-if="isAdmin"
          :contact="contact"
          @deleted="$emit('panelClose')"
        >
          <template #trigger>
            <NextButton
              v-tooltip.top-end="$t('DELETE_CONTACT.BUTTON_LABEL')"
              icon="i-ph-trash"
              slate
              faded
              sm
              ruby
              :disabled="uiFlags.isDeleting"
            />
          </template>
        </ContactDeleteModal>
      </div>

      <div v-if="currentContactId != contact.id" class="mt-1">
        <NextButton
          slate
          faded
          sm
          label="Odoo Contact"
          @click="loadOdooContact"
        />
      </div>

      <div v-if="currentContactId == contact.id" class="mt-1">
        <p class="">{{ 'Odoo Contact' }}</p>
        <div v-if="loadingOdoo">
          {{ 'Loading...' }}
        </div>
        <div v-if="sendedToOdoo && !loadingOdoo">
          <p>{{ 'Contact already forwarded to Odoo' }}</p>
        </div>
        <div v-if="!sendedToOdoo && !loadingOdoo">
          <select
            v-model="selectedOdoo"
            class="border p-2 rounded"
            placeholder="Select Odoo Instance"
            @change="changeOdooInstance"
          >
            <option value="" disabled selected>
              {{ 'Select Odoo Instance' }}
            </option>
            <option v-for="odoo in odoos" :key="odoo.id" :value="odoo.id">
              {{ odoo.odoo_name }}
            </option>
          </select>

          <select
            v-model="selectedAgent"
            :disabled="agents.length <= 0"
            class="border p-2 rounded"
            placeholder="Select Agents"
          >
            <option value="" disabled selected>{{ 'Select Agents' }}</option>
            <option v-for="agent in agents" :key="agent.id" :value="agent.id">
              {{ agent.name }}
            </option>
          </select>

          <textarea
            v-model="comment"
            class="border p-2 rounded w-full mt-2"
            placeholder="Comment"
            rows="3"
            :disabled="!canSendOdoo"
          />

          <div class="flex gap-2">
            <NextButton
              v-tooltip.top-end="'ส่งไปยัง odoo'"
              icon="i-ph-share-fat"
              slate
              faded
              sm
              label="ส่งไปยัง Odoo"
              :disabled="!canSendOdoo"
              @click="sendToOdoo"
            />
            <NextButton
              v-tooltip.top-end="'ส่งไปยัง odoo'"
              icon="i-ph-share-fat"
              slate
              faded
              sm
              :disabled="uiFlags.isMerging"
              @click="sendToOdoo2"
            />
          </div>
        </div>
      </div>
      <EditContact
        :show="showEditModal"
        :contact="contact"
        @cancel="toggleEditModal"
      />
    </div>
  </div>
</template>

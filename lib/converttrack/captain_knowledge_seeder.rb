# frozen_string_literal: true

module Converttrack
  module CaptainKnowledgeSeeder
    module_function

    FAQS = [
      {
        question: 'Quel est le prix du canape Oslo ?',
        answer: 'Le canape Oslo est a 185 000 FCFA. Il est disponible en Bleu, Gris et Beige.'
      },
      {
        question: 'Quel est le delai de livraison a Abidjan ?',
        answer: 'La livraison a Abidjan prend en general 3 a 5 jours ouvrables pour les produits en stock.'
      },
      {
        question: 'Quel est le prix du bureau Ergo ?',
        answer: 'Le bureau Ergo est a 220 000 FCFA. Livraison gratuite a Abidjan sous 5 jours.'
      },
      {
        question: 'Proposez-vous la livraison en province ?',
        answer: 'Oui, nous livrons dans toute la Cote d Ivoire. Les delais varient de 5 a 10 jours selon la ville.'
      },
      {
        question: 'Quels moyens de paiement acceptez-vous ?',
        answer: 'Nous acceptons Mobile Money, virement bancaire et paiement a la livraison sur Abidjan.'
      },
      {
        question: 'Le matelas Confort Plus est-il disponible ?',
        answer: 'Oui, le matelas Confort Plus est en stock a 175 000 FCFA, disponible en 140x190 et 160x200.'
      },
      {
        question: 'Comment suivre ma commande ?',
        answer: 'Apres validation, vous recevez un SMS avec un lien de suivi. Vous pouvez aussi nous ecrire sur WhatsApp.'
      },
      {
        question: 'Quelle est la politique de retour ?',
        answer: 'Retour possible sous 7 jours pour les produits non montes, emballage d origine requis.'
      },
      {
        question: 'Avez-vous des promotions en cours ?',
        answer: 'Consultez notre collection salon : plusieurs articles beneficient de -15% cette semaine.'
      },
      {
        question: 'Quel est le prix de la table basse Natura ?',
        answer: 'La table basse Natura est a 95 000 FCFA, disponible en Chene et Noyer.'
      },
      {
        question: 'L armoire Zen est-elle en stock ?',
        answer: 'L armoire Zen est sur commande a 310 000 FCFA, delai de 10 a 14 jours.'
      },
      {
        question: 'Proposez-vous le montage a domicile ?',
        answer: 'Oui, le montage est disponible a Abidjan pour 15 000 FCFA par piece.'
      },
      {
        question: 'Quels sont vos horaires de support ?',
        answer: 'Notre equipe repond du lundi au samedi, de 8h a 20h (GMT).'
      },
      {
        question: 'Comment contacter un conseiller commercial ?',
        answer: 'Demandez un rappel via le chat ou ecrivez a ventes@demo.converttrack.local.'
      }
    ].freeze

    DOCUMENTS = [
      {
        name: 'Catalogue salon ConvertTrack',
        external_link: 'https://demo.converttrack.local/docs/catalogue-salon',
        content: <<~TEXT.strip
          Collection salon : Canape Oslo (185 000 FCFA), Table basse Natura (95 000 FCFA),
          Set Coussins Deco (18 000 FCFA). Livraison Abidjan 3 a 5 jours.
        TEXT
      },
      {
        name: 'Guide livraison et retours',
        external_link: 'https://demo.converttrack.local/docs/livraison-retours',
        content: <<~TEXT.strip
          Livraison Abidjan : 3 a 5 jours. Province : 5 a 10 jours.
          Retours sous 7 jours, produit non monte, emballage intact.
        TEXT
      },
      {
        name: 'Fiche Bureau Ergo',
        external_link: 'https://demo.converttrack.local/docs/bureau-ergo',
        content: <<~TEXT.strip
          Bureau Ergo : 220 000 FCFA, couleurs Blanc et Noir.
          Livraison gratuite a Abidjan, montage optionnel 15 000 FCFA.
        TEXT
      },
      {
        name: 'Conditions commerciales demo',
        external_link: 'https://demo.converttrack.local/docs/conditions',
        content: <<~TEXT.strip
          Paiement : Mobile Money, virement, paiement a la livraison (Abidjan).
          Support lun-sam 8h-20h. Escalade manager pour clients VIP insatisfaits.
        TEXT
      }
    ].freeze

    def seed!(account:, assistant:)
      seed_faqs!(account: account, assistant: assistant)
      seed_documents!(account: account, assistant: assistant)
    end

    def seed_faqs!(account:, assistant:)
      return if assistant.responses.count >= FAQS.size

      FAQS.each do |faq|
        next if assistant.responses.exists?(question: faq[:question])

        Captain::AssistantResponse.create!(
          account: account,
          assistant: assistant,
          question: faq[:question],
          answer: faq[:answer],
          status: :approved
        )
      end
    end

    def seed_documents!(account:, assistant:)
      return if assistant.documents.count >= DOCUMENTS.size

      DOCUMENTS.each do |doc|
        next if assistant.documents.exists?(name: doc[:name])

        Captain::Document.create!(
          account: account,
          assistant: assistant,
          name: doc[:name],
          external_link: doc[:external_link],
          content: doc[:content],
          status: :available,
          sync_status: :synced
        )
      end
    end
  end
end

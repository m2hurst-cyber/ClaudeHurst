class DocumentMailer < ApplicationMailer
  def send_document
    @document = params[:document]
    @user = params[:user]
    type = @document.class.name
    attachments["#{@document.number}.pdf"] = pdf_for(@document)
    to = @document.company.contacts.where(primary: true).pluck(:email).compact.first || @user&.email
    mail(to: to, subject: "[#{Branding.company_name}] #{type} #{@document.number}")
  end

  private

  def pdf_for(doc)
    case doc
    when Contract then Pdf::ContractPdf.new(doc).render
    else Pdf::DocumentPdf.new(doc).render
    end
  end
end

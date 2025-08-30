import 'models.dart';

const List<ChecklistTemplate> kChecklistTemplates = [
  ChecklistTemplate(
    name: 'Tablero Eléctrico',
    items: [
      ChecklistItemTemplate(title: 'Vista panorámica del tablero'),
      ChecklistItemTemplate(title: 'Identificación y señalización del tablero'),
      ChecklistItemTemplate(title: 'Interruptor principal'),
      ChecklistItemTemplate(title: 'Interruptores secundarios'),
      ChecklistItemTemplate(title: 'Barras de distribución'),
      ChecklistItemTemplate(title: 'Conexiones y cableado interno'),
      ChecklistItemTemplate(title: 'Puesta a tierra'),
      ChecklistItemTemplate(title: 'Estado de la puerta y cerrojo'),
      ChecklistItemTemplate(title: 'Espacio libre de trabajo frontal'),
      ChecklistItemTemplate(title: 'Observaciones adicionales'),
    ],
  ),
  ChecklistTemplate(
    name: 'Inspección de Extintor',
    items: [
      ChecklistItemTemplate(title: 'Ubicación y visibilidad'),
      ChecklistItemTemplate(title: 'Señalización adecuada'),
      ChecklistItemTemplate(title: 'Manómetro de presión (si aplica)'),
      ChecklistItemTemplate(title: 'Sello de seguridad intacto'),
      ChecklistItemTemplate(title: 'Manguera y boquilla'),
      ChecklistItemTemplate(title: 'Estado del cilindro (sin corrosión o daños)'),
      ChecklistItemTemplate(title: 'Fecha de último mantenimiento/recarga'),
      ChecklistItemTemplate(title: 'Tarjeta de inspección'),
      ChecklistItemTemplate(title: 'Observaciones adicionales'),
    ],
  ),
];

const categories = [
  { name: 'Burgers', icon: '🍔' },
  { name: 'Pizza', icon: '🍕' },
  { name: 'Biryani', icon: '🍛' },
  { name: 'Dessert', icon: '🍰' }
];

const restaurants = [
  {
    id: 1,
    name: 'Mashbash Grill',
    item: 'Smash Burger Meal',
    icon: '🍔',
    rating: '4.9',
    time: '18-25 min',
    price: 1199
  },
  {
    id: 2,
    name: 'Urban Pizza Lab',
    item: 'Loaded Pepperoni Pizza',
    icon: '🍕',
    rating: '4.8',
    time: '25-35 min',
    price: 1699
  },
  {
    id: 3,
    name: 'Royal Biryani House',
    item: 'Chicken Biryani Bowl',
    icon: '🍛',
    rating: '4.7',
    time: '20-30 min',
    price: 799
  },
  {
    id: 4,
    name: 'Sweet Cloud',
    item: 'Molten Lava Cake',
    icon: '🍰',
    rating: '4.6',
    time: '15-20 min',
    price: 549
  }
];

const cart = new Map();
const deliveryFee = 149;

const categoryRow = document.querySelector('#categoryRow');
const restaurantList = document.querySelector('#restaurantList');
const cartItems = document.querySelector('#cartItems');
const cartCount = document.querySelector('#cartCount');
const subtotalEl = document.querySelector('#subtotal');
const grandTotalEl = document.querySelector('#grandTotal');
const searchInput = document.querySelector('#searchInput');
const riderForm = document.querySelector('#riderForm');
const riderMessage = document.querySelector('#riderMessage');

function currency(value) {
  return `Rs ${value.toLocaleString('en-PK')}`;
}

function renderCategories() {
  categoryRow.innerHTML = categories
    .map(category => `
      <button class="category-card" data-category="${category.name}">
        <span>${category.icon}</span>
        ${category.name}
      </button>
    `)
    .join('');
}

function renderRestaurants(list = restaurants) {
  restaurantList.innerHTML = list
    .map(restaurant => `
      <article class="restaurant-card">
        <div class="food-img">${restaurant.icon}</div>
        <div>
          <h4>${restaurant.item}</h4>
          <div class="restaurant-meta">
            <span>⭐ ${restaurant.rating}</span>
            <span>⏱ ${restaurant.time}</span>
            <span>${currency(restaurant.price)}</span>
          </div>
          <p class="restaurant-meta">${restaurant.name}</p>
        </div>
        <button class="add-btn" aria-label="Add ${restaurant.item}" data-id="${restaurant.id}">+</button>
      </article>
    `)
    .join('');
}

function renderCart() {
  const items = Array.from(cart.values());
  const subtotal = items.reduce((sum, item) => sum + item.price * item.quantity, 0);
  const totalQuantity = items.reduce((sum, item) => sum + item.quantity, 0);
  const grandTotal = subtotal > 0 ? subtotal + deliveryFee : 0;

  cartCount.textContent = `${totalQuantity} ${totalQuantity === 1 ? 'item' : 'items'}`;
  subtotalEl.textContent = currency(subtotal);
  grandTotalEl.textContent = currency(grandTotal);

  if (!items.length) {
    cartItems.className = 'cart-items empty';
    cartItems.textContent = 'Your cart is empty.';
    return;
  }

  cartItems.className = 'cart-items';
  cartItems.innerHTML = items
    .map(item => `
      <div class="cart-item">
        <div>
          <h4>${item.item}</h4>
          <p>${currency(item.price)}</p>
        </div>
        <div class="qty-controls">
          <button data-action="decrease" data-id="${item.id}">−</button>
          <strong>${item.quantity}</strong>
          <button data-action="increase" data-id="${item.id}">+</button>
        </div>
      </div>
    `)
    .join('');
}

function addToCart(id) {
  const restaurant = restaurants.find(item => item.id === Number(id));
  if (!restaurant) return;

  const existing = cart.get(restaurant.id);
  cart.set(restaurant.id, {
    ...restaurant,
    quantity: existing ? existing.quantity + 1 : 1
  });
  renderCart();
}

function updateQuantity(id, action) {
  const item = cart.get(Number(id));
  if (!item) return;

  const nextQuantity = action === 'increase' ? item.quantity + 1 : item.quantity - 1;
  if (nextQuantity <= 0) {
    cart.delete(Number(id));
  } else {
    cart.set(Number(id), { ...item, quantity: nextQuantity });
  }
  renderCart();
}

function switchSection(section) {
  document.querySelectorAll('.nav-item').forEach(button => {
    button.classList.toggle('active', button.dataset.section === section);
  });

  document.querySelectorAll('.screen-section').forEach(screen => {
    screen.classList.remove('active-screen');
  });

  const target = document.querySelector(`#${section}Section`);
  if (target) target.classList.add('active-screen');
}

restaurantList.addEventListener('click', event => {
  const addButton = event.target.closest('.add-btn');
  if (addButton) addToCart(addButton.dataset.id);
});

cartItems.addEventListener('click', event => {
  const qtyButton = event.target.closest('button[data-action]');
  if (qtyButton) updateQuantity(qtyButton.dataset.id, qtyButton.dataset.action);
});

document.querySelectorAll('.nav-item').forEach(button => {
  button.addEventListener('click', () => switchSection(button.dataset.section));
});

searchInput.addEventListener('input', event => {
  const term = event.target.value.trim().toLowerCase();
  const filtered = restaurants.filter(restaurant =>
    restaurant.item.toLowerCase().includes(term) ||
    restaurant.name.toLowerCase().includes(term)
  );
  renderRestaurants(filtered);
});

riderForm.addEventListener('submit', event => {
  event.preventDefault();
  riderMessage.textContent = 'Demo login successful. Rider dashboard will be added next.';
});

document.querySelector('#checkoutBtn').addEventListener('click', () => {
  if (!cart.size) {
    alert('Please add an item to cart first.');
    return;
  }
  alert('Demo checkout complete. Payment gateway will be connected later.');
});

renderCategories();
renderRestaurants();
renderCart();
